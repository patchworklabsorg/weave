# frozen_string_literal: true

require "rails_helper"

RSpec.describe VerificationFlow do
  include ActiveJob::TestHelper

  let(:member) { create(:user, :verified) }
  let(:verifier) { create(:user, :identity_team) }

  def image = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/id_document.png"), "image/png")

  def identifiers
    VerificationIdentifiers.new(document_type: "passport", issuing_country: "DE", document_number: "C01X00T47",
                                national_id: nil, legal_name: "Erika Mustermann", date_of_birth: Date.new(1990, 8, 12))
  end

  def decide(verification, by: verifier, outcome: "verified", **overrides)
    described_class.decide(verification, by:, outcome:, reason: "Face matched the ID held up on the call.",
                                         age_consistent: true, region_consistent: true, identifiers:, **overrides)
  end

  describe ".submit" do
    it "creates the first attempt and its audit row" do
      result = described_class.submit(member, document: image, document_type: "passport")

      expect(result).to be_success
      expect(result.verification).to have_attributes(status: "submitted", previous_attempt: nil, document_type: "passport")
      expect(result.verification.events.pluck(:kind)).to eq(["submitted"])
    end

    it "stores the image under a neutral file name, so the upload name can't leak the member's name" do
      upload = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/id_document.png"), "image/png",
                                            original_filename: "Jane Doe passport.PNG")

      verification = described_class.submit(member, document: upload, document_type: "passport").verification

      expect(verification.id_document.filename.to_s).to eq("id_document.png")
      expect(ActiveStorage::Blob.where("filename ILIKE ?", "%doe%")).to be_empty
      # The stored copy is the converted image: the same pixels, re-encoded.
      stored = Vips::Image.new_from_buffer(verification.id_document.download, "")
      original = Vips::Image.new_from_buffer(Rails.root.join("spec/fixtures/files/id_document.png").binread, "")
      expect([stored.width, stored.height]).to eq([original.width, original.height])
      expect((stored - original).abs.max).to eq(0)
    end

    it "refuses an upload that does not convert, and stores nothing" do
      upload = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/id_document.webp"), "image/png")

      result = nil
      expect { result = described_class.submit(member, document: upload, document_type: "passport") }
        .not_to change(ActiveStorage::Blob, :count)
      expect(result.errors[:id_document]).to eq(I18n.t("verification.errors.document_unsupported"))
      expect(Verification.count).to eq(0)
    end

    it "links a new attempt to the one before it" do
      first = create(:verification, user: member, status: "needs_resubmission", resubmission_note: "Blurry")

      result = described_class.submit(member, document: image, document_type: "passport")

      expect(result.verification.previous_attempt).to eq(first)
    end

    it "refuses a second attempt while one is in progress" do
      create(:verification, user: member)

      result = described_class.submit(member, document: image, document_type: "passport")

      expect(result).not_to be_success
      expect(result.errors[:base]).to eq(I18n.t("verification.blockers.in_progress"))
    end

    it "refuses an attempt inside the cooldown of a failed call" do
      create(:verification, :failed, user: member, decided_at: 1.day.ago)

      expect(described_class.submit(member, document: image, document_type: "passport")).not_to be_success
    end

    it "allows an attempt after the cooldown" do
      create(:verification, :failed, user: member, decided_at: VerificationSettings.failed_call_cooldown.ago - 1.minute)

      expect(described_class.submit(member, document: image, document_type: "passport")).to be_success
    end

    it "refuses a member with no birthday" do
      member.update_columns(birthday: nil) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.submission_blocker(member)).to eq(:no_birthday)
    end

    it "refuses the digital ID path while no provider exists" do
      result = described_class.submit(member, document: nil, document_type: nil, verification_method: "digital_id_call")

      expect(result.errors[:verification_method]).to eq(I18n.t("verification.errors.digital_id_unavailable"))
    end
  end

  describe "pre-review" do
    let(:verification) { create(:verification, user: member) }

    it "lets an identity team member take the attempt" do
      expect(described_class.start_pre_review(verification, by: verifier)).to be(true)
      expect(verification.reload).to have_attributes(status: "pre_review", pre_reviewer: verifier)
    end

    it "does not let the member take their own attempt, also on the identity team" do
      member.update!(role: :admin, identity_team: true)

      expect(described_class.start_pre_review(verification, by: member)).to be(false)
    end

    it "does not let a user outside the identity team take it" do
      expect(described_class.start_pre_review(verification, by: create(:user, :admin))).to be(false)
    end

    it "shows the image to the pre-reviewer only, and logs each view first" do
      described_class.start_pre_review(verification, by: verifier)

      expect(described_class.pre_review_document(verification, by: create(:user, :identity_team))).to be_nil
      expect(described_class.pre_review_document(verification, by: verifier)).to eq(Rails.root.join("spec/fixtures/files/id_document.png").binread)
      expect(verification.events.where(kind: "document_viewed").sole.actor).to eq(verifier)
    end

    it "sends a document problem back to the member with a note" do
      described_class.start_pre_review(verification, by: verifier)

      expect { described_class.reject_document(verification, by: verifier, note: "The photo is blurry.") }
        .to have_enqueued_mail(VerificationMailer, :status_changed)
      expect(verification.reload).to have_attributes(status: "needs_resubmission", resubmission_note: "The photo is blurry.")
      expect(member.verification_status).to eq("needs_submission")
    end

    it "ends pre-review with Document OK, and the attempt waits for a call time" do
      described_class.start_pre_review(verification, by: verifier)

      expect { described_class.approve_document(verification, by: verifier) }
        .to have_enqueued_mail(VerificationMailer, :status_changed)
      expect(verification.reload).to have_attributes(status: "awaiting_call", call_scheduled_for: nil)
      expect(verification.pre_reviewed_at).to be_present
      expect(verification.events.find_by!(kind: "document_approved").actor).to eq(verifier)
      expect(verification).to be_in_progress
      expect(member.verification_status).to eq("pending")
    end

    it "lets another identity team member take over the pre-review, and logs the hand-over" do
      described_class.start_pre_review(verification, by: verifier)
      other = create(:user, :identity_team)

      expect(described_class.take_over_pre_review(verification, by: other)).to be(true)

      expect(verification.reload.pre_reviewer).to eq(other)
      event = verification.events.find_by!(kind: "pre_review_taken_over")
      expect(event).to have_attributes(actor: other)
      expect(event.data).to include("from_pre_reviewer_id" => verifier.id, "to_pre_reviewer_id" => other.id)
      # Only the new pre-reviewer sees the image and marks the document OK.
      expect(described_class.pre_review_document(verification, by: verifier)).to be_nil
      expect(described_class.pre_review_document(verification, by: other)).to be_present
      expect(described_class.approve_document(verification, by: verifier)).to be(false)
      expect(described_class.approve_document(verification, by: other)).to be(true)
    end

    it "refuses a take-over by the member, someone outside the team, the pre-reviewer, or outside pre-review" do
      expect(described_class.take_over_pre_review(verification, by: create(:user, :identity_team))).to be(false)
      described_class.start_pre_review(verification, by: verifier)

      expect(described_class.take_over_pre_review(verification, by: verifier)).to be(false)
      expect(described_class.take_over_pre_review(verification, by: create(:user, :admin))).to be(false)
      member.update!(role: :admin, identity_team: true)
      expect(described_class.take_over_pre_review(verification, by: member)).to be(false)
      expect(verification.reload.pre_reviewer).to eq(verifier)
      expect(verification.events.where(kind: "pre_review_taken_over")).to be_empty
    end

    it "lets only the pre-reviewer mark the document OK, and only during pre-review" do
      expect(described_class.approve_document(verification, by: verifier)).to be(false)
      described_class.start_pre_review(verification, by: verifier)

      expect(described_class.approve_document(verification, by: create(:user, :identity_team))).to be(false)
      expect(verification.reload).to be_pre_review
    end

    it "closes the image to the pre-reviewer after Document OK" do
      described_class.start_pre_review(verification, by: verifier)
      described_class.approve_document(verification, by: verifier)

      expect(described_class.pre_review_document(verification.reload, by: verifier)).to be_nil
    end

    it "records the agreed call time as a separate step, and moves it" do
      described_class.start_pre_review(verification, by: verifier)
      at = 2.days.from_now.change(usec: 0)
      expect(described_class.schedule_call(verification, by: verifier, at:)).to be(false)

      described_class.approve_document(verification, by: verifier)
      other = create(:user, :identity_team)
      expect { described_class.schedule_call(verification, by: other, at:) }
        .to have_enqueued_mail(VerificationMailer, :status_changed)
      expect(verification.reload).to have_attributes(status: "call_scheduled", call_scheduled_for: at, call_scheduled_by: other)

      expect(described_class.schedule_call(verification, by: other, at: at + 1.day)).to be(true)
      expect(verification.reload.call_scheduled_for).to eq(at + 1.day)
    end

    it "refuses a call time in the past" do
      verification = create(:verification, :awaiting_call, user: member)

      expect(described_class.schedule_call(verification, by: verifier, at: 1.hour.ago)).to be(false)
      expect(verification.reload).to be_awaiting_call
    end
  end

  describe ".decide" do
    let(:verification) { create(:verification, :call_scheduled, user: member) }

    it "records a pass with the attestation and the audit row" do
      result = decide(verification)

      expect(result).to be_success
      expect(verification.reload).to have_attributes(status: "verified", verifier:, age_consistent: true, region_consistent: true)
      event = verification.events.find_by!(kind: "decided")
      expect(event.data).to include("outcome" => "verified", "reason" => "Face matched the ID held up on the call.",
                                    "document_type" => "passport", "age_consistent" => true, "region_consistent" => true)
      expect(event.data["attendees"]).to include("member_id" => member.id, "verifier_id" => verifier.id, "guardian_attended" => false)
      expect(member.verification_status).to eq("verified")
    end

    it "gives the identifiers to the hook and stores none of them" do
      received = nil
      subscriber = ActiveSupport::Notifications.subscribe(VerificationIdentifiers::EVENT) { |event| received = event.payload }

      decide(verification)

      expect(received).to include(verification:, outcome: "verified", identifiers:)
      stored = [Verification.where(id: verification.id).to_a.to_json, VerificationEvent.all.to_a.to_json,
                PaperTrail::Version.all.to_a.to_json]
      %w[C01X00T47 Mustermann 1990-08-12].each { |value| expect(stored.join).not_to include(value) }
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "rolls back the decision when the hook fails" do
      subscriber = ActiveSupport::Notifications.subscribe(VerificationIdentifiers::EVENT) { raise "knot failure" }

      expect { decide(verification) }.to raise_error(/knot failure/)
      expect(verification.reload).to be_call_scheduled
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    it "needs the identifiers for a pass of a document call" do
      result = decide(verification, identifiers: nil)

      expect(result.errors).to include(:identifiers)
    end

    it "does not pass an age or region mismatch" do
      result = decide(verification, age_consistent: false, region_consistent: false)

      expect(result.errors).to include(:age_consistent, :region_consistent)
    end

    it "needs a yes or no for each attestation" do
      result = decide(verification, outcome: "failed", age_consistent: nil)

      expect(result.errors).to include(:age_consistent)
    end

    it "needs a written reason" do
      result = decide(verification, reason: " ")

      expect(result.errors).to include(:reason)
    end

    it "does not let the member verify themselves" do
      member.update!(role: :admin, identity_team: true)

      expect(decide(verification, by: member)).not_to be_success
    end

    it "does not pass a minor without a granted guardian consent" do
      member.update!(birthday: 15.years.ago.to_date)

      expect(decide(verification).errors[:base]).to include("guardian consent")
    end

    it "passes a minor with a granted guardian consent, and records the guardian on the call" do
      member.update!(birthday: 15.years.ago.to_date)
      consent = create(:guardian_consent, :granted, user: member)

      expect(decide(verification, guardian_attended: true)).to be_success
      expect(verification.reload.guardian_consent).to eq(consent)
    end

    it "does not pass a minor when no guardian attended the call, even with a granted consent" do
      member.update!(birthday: 15.years.ago.to_date)
      create(:guardian_consent, :granted, user: member)

      result = decide(verification)

      expect(result).not_to be_success
      expect(result.errors[:guardian_attended]).to include("must attend")
      expect(verification.reload).to be_call_scheduled
    end

    it "can still fail a minor when no guardian attended" do
      member.update!(birthday: 15.years.ago.to_date)
      consent = create(:guardian_consent, :granted, user: member)

      expect(decide(verification, outcome: "failed")).to be_success
      expect(verification.reload).to have_attributes(status: "failed", guardian_consent: consent, guardian_attended: false)
      expect(verification.events.find_by!(kind: "decided").data.dig("attendees", "guardian_consent_id")).to eq(consent.id)
    end

    it "does not ask an adult for a guardian" do
      expect(decide(verification, guardian_attended: false)).to be_success
    end

    it "takes a second verifier from the identity team" do
      second = create(:user, :identity_team)

      decide(verification, second_verifier: second)

      expect(verification.reload.second_verifier).to eq(second)
    end

    it "lets a break-glass key holder verify a member" do
      expect(decide(verification, by: create(:user, :key_holder))).to be_success
      expect(verification.reload).to be_verified
    end

    it "takes a break-glass key holder as the second verifier" do
      second = create(:user, :key_holder)

      expect(decide(verification, second_verifier: second)).to be_success
      expect(verification.reload.second_verifier).to eq(second)
    end

    it "refuses a second verifier outside the identity team" do
      expect(decide(verification, second_verifier: create(:user)).errors).to include(:second_verifier)
    end

    describe "a retry after a failed call" do
      let!(:failed) { create(:verification, :failed, user: member, verifier:, decided_at: 1.month.ago) }
      let(:retry_attempt) { create(:verification, :call_scheduled, user: member, previous_attempt: failed) }

      it "refuses the verifier who failed the member before" do
        result = decide(retry_attempt, by: verifier)

        expect(result.errors[:verifier]).to include("different verifier")
      end

      it "refuses that verifier as the second verifier too" do
        result = decide(retry_attempt, by: create(:user, :identity_team), second_verifier: verifier)

        expect(result.errors).to include(:second_verifier)
      end

      it "accepts a different verifier" do
        expect(decide(retry_attempt, by: create(:user, :identity_team))).to be_success
      end
    end

    describe "escalation" do
      before do
        (VerificationSettings.failed_calls_before_escalation - 1).times { create(:verification, :failed, user: member, decided_at: 2.months.ago) }
      end

      it "sends the attempt to the lead at the configured number of fails" do
        lead = create(:user, :identity_lead)

        expect { decide(verification, outcome: "failed", identifiers: nil) }
          .to have_enqueued_mail(VerificationMailer, :escalated).with(verification, lead)
        expect(verification.reload.escalation_open?).to be(true)
        expect(member.verification_status).to eq("pending")
        expect(described_class.submission_blocker(member)).to eq(:escalated)
      end

      it "lets the lead allow one more round" do
        lead = create(:user, :identity_lead)
        decide(verification, outcome: "failed", identifiers: nil)

        expect(described_class.resolve_escalation(verification, by: lead, resolution: "retry_allowed", note: "Bad camera"))
          .to be(true)
        expect(member.verification_status).to eq("needs_submission")
        expect(described_class.failed_calls_since_reset(member)).to eq(0)
      end

      it "lets the lead close the case" do
        lead = create(:user, :identity_lead)
        decide(verification, outcome: "failed", identifiers: nil)

        described_class.resolve_escalation(verification, by: lead, resolution: "ineligible", note: "Different person each call")

        expect(member.verification_status).to eq("ineligible")
        expect(described_class.submission_blocker(member)).to eq(:ineligible)
      end

      it "does not let a team member who is not a lead resolve it" do
        decide(verification, outcome: "failed", identifiers: nil)

        expect(described_class.resolve_escalation(verification, by: create(:user, :identity_team), resolution: "ineligible", note: "x"))
          .to be(false)
      end
    end
  end
end
