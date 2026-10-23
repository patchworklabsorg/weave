# frozen_string_literal: true

require "rails_helper"

RSpec.describe ResidencyFlow do
  include ActiveJob::TestHelper

  let(:member) { create(:user, :verified, legal_first_name: "Erika", legal_last_name: "Mustermann", birthday: Date.new(2009, 8, 12)) }
  let(:verifier) { create(:user, :identity_team) }

  # The end of pre-review seals the documents (see ResidencyDocumentVault).
  before { active_key_set_without_holders }

  def upload = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/id_document.png"), "image/png")

  def identity_verified!(user = member) = create(:verification, :verified, user:)

  # A document review in pre-review by the verifier.
  def review_in_pre_review
    identity_verified!
    check = ResidencyFlow.submit_document(member, document: upload, evidence_type: "school_enrollment").verification
    ResidencyFlow.start_pre_review(check, by: verifier)
    check.reload
  end

  def decide_yes(check, state: "MA", evidence: "school_enrollment")
    ResidencyFlow.decide_review(check, by: verifier, us_resident: true, us_state: state, evidence_type: evidence)
  end

  describe ".status" do
    it "starts at needs_check, and a check without a call needs identity verification first" do
      expect(described_class.status(member)).to eq("needs_check")
      expect(described_class.submission_blocker(member)).to eq(:identity_needed)
      expect(member.us_resident?).to be_nil
    end
  end

  describe "a document review" do
    it "stores the document under Lockbox and opens a pending check" do
      identity_verified!
      result = described_class.submit_document(member, document: upload, evidence_type: "school_enrollment")

      expect(result).to be_success
      check = result.verification
      expect(check).to have_attributes(source: "document_review", status: "submitted", evidence_type: "school_enrollment")
      expect(check.document.filename.to_s).to eq("residency_document.png")
      expect(described_class.status(member)).to eq("pending")
      expect(described_class.submission_blocker(member)).to eq(:in_progress)
    end

    it "refuses an evidence type that does not show residency" do
      identity_verified!
      result = described_class.submit_document(member, document: upload, evidence_type: "passport")

      expect(result).not_to be_success
      expect(result.errors).to include(:evidence_type)
    end

    it "lets only the pre-reviewer open the document, and records a yes with the state" do # rubocop:disable RSpec/MultipleExpectations
      check = review_in_pre_review
      other = create(:user, :identity_team)

      expect(described_class.pre_review_document(check, by: other)).to be_nil
      expect(described_class.pre_review_document(check, by: verifier)).to be_present

      expect { decide_yes(check) }.to have_enqueued_mail(ResidencyMailer, :status_changed)
      check.reload
      expect(check).to have_attributes(status: "decided", us_resident: true, us_state: "MA", decided_by: verifier)
      expect(check.document).not_to be_attached
      expect(check.document_sealed?).to be(true)
      expect(member.us_residency_status).to eq("us_resident")
      expect(member.us_resident?).to be(true)
      expect(member.us_residency_checked_on).to eq(Date.current)
      expect(described_class.pre_review_document(check, by: verifier)).to be_nil
    end

    it "needs a US state for a yes, and keeps no state for a no" do
      check = review_in_pre_review

      expect(decide_yes(check, state: "XX").errors).to include(:us_state)
      result = described_class.decide_review(check, by: verifier, us_resident: false, us_state: "MA", evidence_type: "school_enrollment")

      expect(result).to be_success
      expect(check.reload).to have_attributes(us_resident: false, us_state: nil)
      expect(member.us_residency_status).to eq("not_us_resident")
    end

    it "sends a document back with a note and seals it" do
      check = review_in_pre_review

      expect(described_class.reject_document(check, by: verifier, note: "The page is cut off.")).to be(true)
      expect(check.reload).to have_attributes(status: "needs_resubmission", resubmission_note: "The page is cut off.")
      expect(check.document_sealed?).to be(true)
      expect(described_class.submission_blocker(member)).to be_nil
    end

    it "does not let a verifier review their own check" do
      identity_verified!(verifier)
      check = described_class.submit_document(verifier, document: upload, evidence_type: "id_document").verification

      expect(described_class.start_pre_review(check, by: verifier)).to be(false)
    end
  end

  describe ".declare_non_resident" do
    it "records a no without a document, and replaces a yes" do
      check = review_in_pre_review
      decide_yes(check)

      expect(described_class.declare_non_resident(member)).to be_success
      expect(member.us_residency_status).to eq("not_us_resident")
      expect(check.reload).to have_attributes(end_reason: "replaced")
      expect(member.residency_checks.order(:id).last.evidence_type).to eq(ResidencyCheck::MEMBER_STATEMENT)
    end
  end

  describe "how long a result stands" do
    it "ends a yes after the valid months, and allows a renewal in the reminder window" do
      check = review_in_pre_review
      decide_yes(check)

      expect(described_class.submission_blocker(member)).to eq(:standing)
      travel(VerificationSettings.residency_valid_for - VerificationSettings.residency_renewal_reminder + 1.day) do
        expect(described_class.submission_blocker(member)).to be_nil
        expect(member.us_residency_status).to eq("us_resident")
      end
      travel(VerificationSettings.residency_valid_for + 1.day) do
        expect(member.us_residency_status).to eq("needs_check")
        expect(member.us_resident?).to be_nil
      end
    end

    it "keeps a no with no time limit" do
      identity_verified!
      described_class.declare_non_resident(member)

      travel(3.years) { expect(member.us_residency_status).to eq("not_us_resident") }
    end

    it "ends a yes when the shipping address moves to another state, but not for a change in the same state" do
      address = member.create_shipping_address!(line1: "1 Main St", city: "Boston", state: "MA", postal_code: "02101", country: "US")
      check = review_in_pre_review
      decide_yes(check)

      address.update!(line1: "2 Main St")
      expect(member.us_residency_status).to eq("us_resident")

      expect { address.update!(state: "NY", city: "Albany", postal_code: "12207") }.to have_enqueued_mail(ResidencyMailer, :ended)
      expect(check.reload).to have_attributes(end_reason: "address_changed")
      expect(member.us_residency_status).to eq("needs_check")
    end
  end

  describe "on the identity call" do
    let(:identifiers) do
      VerificationIdentifiers.new(document_type: "other", issuing_country: "US", document_number: "S1234567", national_id: nil,
                                  legal_name: "Erika Mustermann", date_of_birth: member.birthday)
    end

    def submit_with_residency
      VerificationFlow.submit(member, document: upload, document_type: "other", residency_document: upload,
                                      residency_evidence_type: "school_enrollment").verification
    end

    def call_scheduled(verification)
      VerificationFlow.start_pre_review(verification, by: verifier)
      VerificationFlow.approve_document(verification.reload, by: verifier)
      VerificationFlow.schedule_call(verification.reload, by: verifier, at: 1.day.from_now)
      verification.reload
    end

    def decide(verification, outcome: "verified", residency: { us_resident: true, us_state: "CA", evidence_type: "school_enrollment" })
      create(:guardian_consent, :granted, user: member) unless member.guardian_consent_granted?
      VerificationFlow.decide(verification, by: verifier, outcome:, reason: "Face matched the ID on the call.", age_consistent: true,
                                            region_consistent: true, guardian_attended: true, identifiers:, residency:)
    end

    it "takes the proof document with the ID, seals it at Document OK, and records the result at the pass" do # rubocop:disable RSpec/MultipleExpectations
      verification = submit_with_residency
      check = described_class.check_for(verification)
      expect(check).to have_attributes(source: "identity_call", status: "submitted", evidence_type: "school_enrollment")
      expect(described_class.status(member)).to eq("pending")

      verification = call_scheduled(verification)
      expect(check.reload.document_sealed?).to be(true)

      expect(decide(verification)).to be_success
      expect(check.reload).to have_attributes(status: "decided", us_resident: true, us_state: "CA", decided_by: verifier)
      expect(member.us_residency_status).to eq("us_resident")
      expect(verification.events.pluck(:kind)).to include("residency_recorded")
    end

    it "needs a residency result for a pass" do
      verification = call_scheduled(VerificationFlow.submit(member, document: upload, document_type: "other").verification)

      result = decide(verification, residency: {})

      expect(result.errors).to include(:us_resident)
      expect(verification.reload).to be_call_scheduled
    end

    it "needs the uploaded document for evidence other than the ID" do
      verification = call_scheduled(VerificationFlow.submit(member, document: upload, document_type: "other").verification)

      result = decide(verification)

      expect(result.errors[:residency_evidence]).to include("proof document")
    end

    it "accepts the ID itself as evidence, with no upload" do
      verification = call_scheduled(VerificationFlow.submit(member, document: upload, document_type: "other").verification)

      expect(decide(verification, residency: { us_resident: true, us_state: "TX", evidence_type: "id_document" })).to be_success
      expect(described_class.current_check(member)).to have_attributes(source: "identity_call", us_state: "TX", evidence_type: "id_document")
    end

    it "records a no on a pass" do
      verification = call_scheduled(VerificationFlow.submit(member, document: upload, document_type: "other").verification)

      expect(decide(verification, residency: { us_resident: false })).to be_success
      expect(member.us_residency_status).to eq("not_us_resident")
    end

    it "gives no result when the call fails" do
      verification = call_scheduled(submit_with_residency)

      decide(verification, outcome: "failed")

      expect(described_class.check_for(verification)).to have_attributes(status: "needs_resubmission", us_resident: nil)
      expect(member.us_residency_status).to eq("needs_check")
    end
  end

  describe RenewResidencyChecksJob do
    it "reminds the member once, before the result ends" do
      check = review_in_pre_review
      decide_yes(check)

      travel(VerificationSettings.residency_valid_for - VerificationSettings.residency_renewal_reminder + 1.day) do
        expect { described_class.perform_now }.to have_enqueued_mail(ResidencyMailer, :renewal_due)
        expect { described_class.perform_now }.not_to have_enqueued_mail(ResidencyMailer, :renewal_due)
      end
    end
  end

  describe PurgeVerificationDocumentsJob do
    it "purges a residency document on the ID image schedule" do
      check = review_in_pre_review
      decide_yes(check)

      described_class.perform_now
      expect(check.reload.document_sealed?).to be(true)

      travel(VerificationSettings.purge_image_after_pass + 1.minute) { described_class.perform_now }
      expect(check.reload.document_purged_at).to be_present
      expect(check.sealed_document).to be_nil
      expect(check.us_resident).to be(true)
    end
  end
end
