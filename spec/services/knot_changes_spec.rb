# frozen_string_literal: true

require "rails_helper"

RSpec.describe KnotChanges do
  let(:knot) { create(:knot, :with_audit) }
  let(:member) { knot.user }
  let(:asker) { create(:user, :identity_team) }
  let(:signer) { create(:user, :identity_team) }

  def name_ids(**overrides)
    defaults = {
      document_type: nil,
      issuing_country: nil,
      document_number: nil,
      national_id: nil,
      legal_name: "Erika Neu",
      date_of_birth: Date.new(1990, 8, 12)
    }
    VerificationIdentifiers.new(**defaults, **overrides)
  end

  describe "the blacklist flag" do
    it "needs a second identity team member to sign off" do
      request = described_class.request_blacklist(knot, by: asker, blacklisted: true, reason: "Cycled a grant.").request

      expect(knot.reload).not_to be_blacklisted
      expect(described_class.sign_off(request, by: asker)).not_to be_success

      expect(described_class.sign_off(request, by: signer)).to be_success
      expect(knot.reload).to be_blacklisted
    end

    it "keeps the reason in the verification audit record and no history on the Knot" do
      request = described_class.request_blacklist(knot, by: asker, blacklisted: true, reason: "Cycled a grant.").request
      described_class.sign_off(request, by: signer)

      events = knot.audit_verification.events
      expect(events.find_by(kind: "knot_change_requested").data).to include("reason" => "Cycled a grant.", "change" => "set_blacklist")
      expect(events.find_by(kind: "knot_change_signed_off").actor).to eq(signer)
      expect(KnotChangeRequest.count).to eq(0)
      expect(knot.reload.attributes.keys).to contain_exactly("id", "user_id", "blacklisted")
    end

    it "clears the flag the same way" do
      knot.update!(blacklisted: true)
      request = described_class.request_blacklist(knot, by: asker, blacklisted: false, reason: "Appeal upheld.").request

      described_class.sign_off(request, by: signer)

      expect(knot.reload).not_to be_blacklisted
    end

    it "makes the member verify again after the review, with the reason recorded" do
      pass = create(:verification, :verified, user: member)
      request = described_class.request_blacklist(knot, by: asker, blacklisted: true, reason: "Cycled a grant.").request

      expect { described_class.sign_off(request, by: signer) }
        .to have_enqueued_mail(VerificationMailer, :status_changed).with(pass)

      expect(pass.reload.reverification_reason).to eq("blacklist_review")
      expect(member.reload.verification_status).to eq("needs_submission")
      expect(pass.events.find_by!(kind: "reverification_required").actor).to eq(signer)
    end

    it "does not ask for a new call when the review is declined" do
      pass = create(:verification, :verified, user: member)
      request = described_class.request_blacklist(knot, by: asker, blacklisted: true, reason: "Cycled a grant.").request

      described_class.decline(request, by: signer, reason: "Not enough evidence.")

      expect(pass.reload.reverification_required_at).to be_nil
    end

    it "works on a detached Knot" do
      knot.update!(user: nil)
      request = described_class.request_blacklist(knot, by: asker, blacklisted: true, reason: "Fraud report.").request

      expect(described_class.sign_off(request, by: signer)).to be_success
      expect(knot.reload).to be_blacklisted
    end

    it "refuses a reasonless request, a non-team asker and the member's own Knot" do
      expect(described_class.request_blacklist(knot, by: asker, blacklisted: true, reason: " ").errors).to include(:reason)
      expect(described_class.request_blacklist(knot, by: create(:user, :admin), blacklisted: true, reason: "x")).not_to be_success
      member.update!(role: :admin, identity_team: true)
      expect(described_class.request_blacklist(knot, by: member, blacklisted: true, reason: "x")).not_to be_success
    end

    it "refuses a second request of the same kind while one waits" do
      described_class.request_blacklist(knot, by: asker, blacklisted: true, reason: "One.")

      expect(described_class.request_blacklist(knot, by: signer, blacklisted: true, reason: "Two.")).not_to be_success
    end

    it "lets the signer decline, with a reason in the audit record" do
      request = described_class.request_blacklist(knot, by: asker, blacklisted: true, reason: "Cycled a grant.").request

      expect(described_class.decline(request, by: signer, reason: "Not enough evidence.")).to be_success
      expect(knot.reload).not_to be_blacklisted
      expect(knot.audit_verification.events.find_by(kind: "knot_change_declined").data).to include("reason" => "Not enough evidence.")
    end

    it "needs a verification audit record to hold the reason" do
      bare = create(:knot)

      expect(described_class.request_blacklist(bare, by: asker, blacklisted: true, reason: "x").errors[:base]).to include("audit")
    end
  end

  describe "a legal name change" do
    def request_change
      described_class.request_name_change(member, by: asker, evidence: "change_of_name_record",
                                                  note: "Saw the marriage certificate on a call.", identifiers: name_ids)
    end

    it "keeps only hashes on the request and changes nothing before the sign-off" do
      create(:knot_hash, knot:, kind: "soft")

      result = request_change

      expect(result).to be_success
      expect(knot.knot_hashes.count).to eq(1)
      expect(result.request.digests.to_json).not_to include("Neu")
    end

    it "adds the new hashes after a second sign-off, keeps the old ones and the standing" do
      old = create(:knot_hash, knot:, kind: "soft")
      knot.update!(blacklisted: true)
      create(:program_grant, knot:)

      expect(described_class.sign_off(request_change.request, by: signer)).to be_success
      expect(knot.reload.knot_hashes.pluck(:kind)).to contain_exactly("soft", "soft")
      expect(knot.knot_hashes).to include(old)
      expect(knot).to be_blacklisted
      expect(knot.program_grants.count).to eq(1)
    end

    it "ends the member's pass at the sign-off, once, with the reason recorded" do
      pass = create(:verification, :verified, user: member)

      expect { described_class.sign_off(request_change.request, by: signer) }
        .to have_enqueued_mail(VerificationMailer, :status_changed).with(pass).once
      expect(pass.reload.reverification_reason).to eq("legal_name_changed")
      expect(member.reload.verification_status).to eq("needs_submission")

      # The same name change, typed into the account later, fires nothing new.
      member.update!(legal_last_name: "Neu")
      expect(VerificationEvent.where(kind: "reverification_required", user_id: member.id).count).to eq(1)
    end

    it "does not end the pass before the sign-off" do
      pass = create(:verification, :verified, user: member)

      request_change

      expect(pass.reload.reverification_required_at).to be_nil
    end

    it "adds a strong hash for a new document" do
      result = described_class.request_name_change(
        member, by: asker, evidence: "new_document", note: "New passport after marriage.",
                identifiers: name_ids(document_type: "passport", issuing_country: "DE", document_number: "C77NEW")
      )
      described_class.sign_off(result.request, by: signer)

      expect(knot.reload.knot_hashes.pluck(:kind)).to contain_exactly("document", "soft")
    end

    it "needs the document fields for a new document, and a continuity note" do
      expect(described_class.request_name_change(member, by: asker, evidence: "new_document", note: "x",
                                                         identifiers: name_ids).errors).to include(:document_number)
      expect(described_class.request_name_change(member, by: asker, evidence: "change_of_name_record", note: "",
                                                         identifiers: name_ids).errors).to include(:note)
    end

    it "needs a member who passed verification" do
      expect(described_class.request_name_change(create(:user), by: asker, evidence: "change_of_name_record",
                                                                note: "x", identifiers: name_ids)).not_to be_success
    end

    it "can't be signed off by the requester" do
      request = described_class.request_name_change(member, by: asker, evidence: "change_of_name_record", note: "x",
                                                            identifiers: name_ids).request

      expect(described_class.sign_off(request, by: asker)).not_to be_success
      expect(knot.reload.knot_hashes).to be_empty
    end
  end
end
