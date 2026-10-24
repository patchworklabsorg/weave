# frozen_string_literal: true

require "rails_helper"

# The US residency check: the member's side and the identity team's queue.
RSpec.describe "US residency check", type: :request do
  let(:member) { create(:user, :verified) }
  let(:verifier) { create(:user, :verified, :identity_team) }
  let(:document) { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/id_document.png"), "image/png") }

  before { active_key_set_without_holders }

  describe "the member" do
    before { sign_in_via_magic_link(member) }

    it "sees that the check comes with identity verification, and never a question about citizenship" do
      get verification_path

      expect(response.body).to include(I18n.t("residency.page.title"), I18n.t("residency.page.identity_first"),
                                       I18n.t("residency.page.submission_title"))
      expect(response.body).not_to match(/name="[^"]*citizen/i)
    end

    it "uploads a document after identity verification" do
      create(:verification, :verified, user: member)

      expect do
        post verification_residency_path, params: { evidence_type: "school_enrollment", residency_document: document }
      end.to change(member.residency_checks, :count).by(1)

      expect(response).to redirect_to(verification_path)
      follow_redirect!
      expect(response.body).to include(I18n.t("residency.page.pending"))
    end

    it "says they do not live in the US" do
      create(:verification, :verified, user: member)

      post not_resident_verification_residency_path

      expect(member.us_residency_status).to eq("not_us_resident")
    end

    it "can't upload before identity verification" do
      post verification_residency_path, params: { evidence_type: "school_enrollment", residency_document: document }

      expect(flash[:alert]).to eq(I18n.t("residency.blockers.identity_needed"))
      expect(member.residency_checks).to be_empty
    end

    it "adds a proof document to an identity submission" do
      post verification_path, params: { document_type: "passport", id_document: document, data_notice_read: "1",
                                        residency_evidence_type: "guardian_state_id", residency_document: document
}

      check = member.residency_checks.sole
      expect(check).to have_attributes(source: "identity_call", evidence_type: "guardian_state_id", verification: member.latest_verification)
    end
  end

  describe "the identity team" do
    let!(:check) do
      create(:verification, :verified, user: member)
      ResidencyFlow.submit_document(member, document:, evidence_type: "guardian_id_and_proof_of_address").verification
    end

    before { sign_in_via_magic_link(verifier) }

    it "lists the check, takes it, and records a yes" do
      get identity_residency_checks_path
      expect(response.body).to include(check.public_id)

      patch start_pre_review_identity_residency_check_path(check)
      get identity_residency_check_path(check)
      expect(response.body).to include("Show the document", "Record the result")

      post image_identity_residency_check_path(check)
      expect(response.parsed_body).to include("data")
      expect(response.headers["Cache-Control"]).to include("no-store")

      patch decide_identity_residency_check_path(check), params: { us_resident: "yes", us_state: "OR", evidence_type: "guardian_id_and_proof_of_address" }

      expect(check.reload).to have_attributes(status: "decided", us_resident: true, us_state: "OR", decided_by: verifier)
      expect(member.us_residency_status).to eq("us_resident")
    end

    it "does not open the document for anyone but the pre-reviewer" do
      ResidencyFlow.start_pre_review(check, by: create(:user, :identity_team))

      post image_identity_residency_check_path(check)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
