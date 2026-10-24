# frozen_string_literal: true

require "rails_helper"

# The identity team's admin pages: queue, pre-review, call outcome,
# escalations, break-glass and the board report.
RSpec.describe "Admin identity verification", type: :request do
  include ActiveJob::TestHelper

  let(:member) { create(:user, :verified, first_name: "Ada") }
  let(:verifier) { create(:user, :identity_team) }

  def image = Rails.root.join("spec/fixtures/files/id_document.png").binread

  # The secure viewer's POST answer: the bytes as Base64 in JSON.
  def viewer_image = Base64.strict_decode64(response.parsed_body["data"])

  def expect_secure_image_headers
    # Rails reduces "no-store, no-cache" to "no-store", the stronger one.
    expect(response.headers["Cache-Control"]).to include("no-store")
    expect(response.headers["Pragma"]).to eq("no-cache")
    expect(response.headers["Content-Disposition"]).to start_with("attachment")
    expect(response.media_type).to eq("application/json")
  end

  describe "access" do
    it "turns away an admin who is not on the identity team" do
      sign_in_via_magic_link(create(:user, :admin, :verified))

      get admin_verifications_path

      expect(response).to redirect_to(admin_root_path)
    end

    it "shows the queue and the nav link to the identity team" do
      create(:verification, user: member)
      sign_in_via_magic_link(verifier)

      get admin_verifications_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Waiting for pre-review", "Ada", %(href="#{admin_verifications_path}"))
    end

    it "finds an attempt by its public id and not by its database id" do
      verification = create(:verification, user: member)
      sign_in_via_magic_link(verifier)

      expect(admin_verification_path(verification)).to eq("/admin/verifications/#{verification.hashid}")
      get "/admin/verifications/#{verification.id}"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "pre-review" do
    let(:verification) { create(:verification, user: member) }

    before { sign_in_via_magic_link(verifier) }

    it "takes the attempt and gives the image to the secure viewer of the pre-reviewer, with a log row" do
      patch start_pre_review_admin_verification_path(verification)
      post image_admin_verification_path(verification)

      expect(viewer_image).to eq(image)
      expect(response.parsed_body).to include("content_type" => "image/png")
      expect(response.parsed_body["watermark"]).to include("name" => verifier.full_name, "pId" => verifier.p_id,
                                                           "subjectId" => verification.public_id)
      expect(response.parsed_body.dig("watermark", "time")).to match(/\A\d{4}-\d\d-\d\dT.*Z\z/)
      expect_secure_image_headers
      expect(verification.events.where(kind: "document_viewed").count).to eq(1)
    end

    it "shows the viewer in the page, with no image link and no new tab" do
      patch start_pre_review_admin_verification_path(verification)
      get admin_verification_path(verification)

      expect(response.body).to include('data-controller="secure-image"', image_admin_verification_path(verification))
      expect(response.body).not_to include('target="_blank"')
      expect(response.body).not_to match(/<img[^>]+#{verification.hashid}/)
    end

    it "has no route that serves the raw image" do
      routes = Rails.application.routes.routes.map { |route| [route.verb, route.path.spec.to_s] }
      expect(routes.map(&:last).grep(%r{/(verifications|break_glass_records)/:id/document})).to be_empty
      image_routes = routes.select { |_verb, path| path.match?(%r{/(verifications|break_glass_records)/:id/image}) }
      expect(image_routes.map(&:first).uniq).to eq(["POST"])
    end

    it "does not open the image before pre-review" do
      post image_admin_verification_path(verification)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).not_to have_key("data")
      expect_secure_image_headers
      expect(verification.events.where(kind: "document_viewed")).to be_empty
    end

    it "asks for a new document with a note" do
      patch start_pre_review_admin_verification_path(verification)
      patch reject_document_admin_verification_path(verification), params: { note: "The photo is blurry." }

      expect(verification.reload).to be_needs_resubmission
    end

    it "marks the document OK, then records the agreed call time" do
      patch start_pre_review_admin_verification_path(verification)
      get admin_verification_path(verification)
      expect(response.body).to include("Document OK", "Send back")

      patch approve_document_admin_verification_path(verification)
      expect(verification.reload).to be_awaiting_call
      expect(flash[:notice]).to include("email or Slack")

      get admin_verification_path(verification)
      expect(response.body).to include("Record the agreed call time")
      expect(response.body).not_to include(image_admin_verification_path(verification))
      get admin_verifications_path
      expect(response.body).to include("Document OK: agree a call time")

      patch schedule_call_admin_verification_path(verification), params: { call_scheduled_for: 2.days.from_now.strftime("%Y-%m-%dT%H:%M") }

      expect(verification.reload).to be_call_scheduled
    end

    it "lets another verifier take over the pre-review from the page" do
      patch start_pre_review_admin_verification_path(verification)
      other = create(:user, :identity_team)
      sign_in_via_magic_link(other)

      get admin_verification_path(verification)
      expect(response.body).to include("Take over pre-review")
      expect(response.body).not_to include(approve_document_admin_verification_path(verification))

      patch take_over_pre_review_admin_verification_path(verification)

      expect(verification.reload.pre_reviewer).to eq(other)
      expect(flash[:notice]).to include("hand-over is logged")
      get admin_verification_path(verification)
      expect(response.body).to include("Document OK", image_admin_verification_path(verification))
      expect(response.body).not_to include("Take over pre-review")
    end

    it "does not record a call time before the document is OK" do
      patch start_pre_review_admin_verification_path(verification)
      patch schedule_call_admin_verification_path(verification), params: { call_scheduled_for: 2.days.from_now.strftime("%Y-%m-%dT%H:%M") }

      expect(verification.reload).to be_pre_review
    end
  end

  describe "recording the call outcome" do
    let(:member) { create(:user, :verified, first_name: "Ada", legal_first_name: "Erika", legal_last_name: "Mustermann", birthday: Date.new(1990, 8, 12)) }
    let(:verification) { create(:verification, :call_scheduled, user: member) }
    let(:params) do
      {
        outcome: "verified", reason: "Face matched the ID held up on the call.", age_consistent: "yes", region_consistent: "yes",
        identifiers: {
          document_type: "passport", issuing_country: "DE", document_number: "C01X00T47",
          legal_name: "Erika Mustermann", date_of_birth: "1990-08-12"
        }
      }
    end

    before { sign_in_via_magic_link(verifier) }

    it "shows the attestation form and no recording field" do
      get admin_verification_path(verification)

      expect(response.body).to include("Consistency attestation", "Never check gender",
                                       "Weave keeps document and national ID numbers only as one-way hashes for the fraud check. " \
                                       "The name and birthday must match the member's account.")
      expect(response.body).not_to include("Mustermann", "1990-08-12")
      expect(response.body).not_to match(/name="[^"]*(video|recording)/)
    end

    it "records a pass and stores no identifier" do
      patch decide_admin_verification_path(verification), params: params

      expect(verification.reload).to be_verified
      expect(member.verification_status).to eq("verified")
      stored = Verification.where(id: verification.id).to_a.to_json + VerificationEvent.all.to_a.to_json +
               PaperTrail::Version.where(item_type: "Verification").to_a.to_json
      expect(stored).not_to include("C01X00T47", "Mustermann")
    end

    it "shows which field differs after a mismatch, keeps the typed entry and never shows the account value" do
      patch decide_admin_verification_path(verification),
            params: params.deep_merge(identifiers: { legal_name: "Erika Musterfrau", date_of_birth: "1990-08-13" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(verification.reload).to be_call_scheduled
      expect(response.body).to include("legal name and birthday you typed do not match",
                                       "The name does not match the account.", "The birthday does not match the account.",
                                       'value="Erika Musterfrau"', "Failed: details don&#39;t match the account")
      expect(response.body).not_to include("Mustermann", "1990-08-12")
    end

    it "fails the call for details that don't match the account" do
      patch decide_admin_verification_path(verification), params: { details_mismatch: "1", reason: "" }

      expect(verification.reload).to be_failed
      expect(verification.decision_reason).to eq(VerificationFlow::DETAILS_MISMATCH_REASON)
    end

    it "gives a key holder the outcome form" do
      sign_in_via_magic_link(create(:user, :key_holder, :verified))

      get admin_verification_path(verification)

      expect(response.body).to include(decide_admin_verification_path(verification))
    end

    it "explains a refusal" do
      patch decide_admin_verification_path(verification), params: params.merge(age_consistent: "no")

      expect(verification.reload).to be_call_scheduled
      expect(flash[:alert]).to include("Age consistent")
    end
  end

  describe "escalations" do
    it "lets the lead resolve one" do
      lead = create(:user, :identity_lead)
      verification = create(:verification, :failed, user: member, escalated_at: 1.hour.ago)
      sign_in_via_magic_link(lead)

      patch resolve_escalation_admin_verification_path(verification), params: { resolution: "retry_allowed", note: "Camera problems" }

      expect(verification.reload.escalation_resolution).to eq("retry_allowed")
    end
  end

  describe "break-glass" do
    let(:verification) { create(:verification, :verified, user: member) }
    let(:holder_a) { create(:user, :key_holder) }
    let(:holder_b) { create(:user, :key_holder) }

    def request_and_approve
      sign_in_via_magic_link(verifier)
      post admin_verification_break_glass_records_path(verification), params: { reason: "Fraud report: compare the document." }
      record = BreakGlassRecord.last
      [holder_a, holder_b].each do |holder|
        sign_in_via_magic_link(holder)
        patch approve_admin_break_glass_record_path(record)
      end
      record.reload
    end

    it "shows the break-glass button only after a decision" do
      sign_in_via_magic_link(verifier)
      get admin_verification_path(verification)
      expect(response.body).to include("Ask for break-glass access")

      scheduled = create(:verification, :call_scheduled, user: create(:user, :verified))
      get admin_verification_path(scheduled)
      expect(response.body).not_to include("Ask for break-glass access")
    end

    it "refuses a break-glass request before the decision, with the reason" do
      scheduled = create(:verification, :awaiting_call, user: create(:user, :verified))
      sign_in_via_magic_link(verifier)

      post admin_verification_break_glass_records_path(scheduled), params: { reason: "Fraud report: compare the document." }

      expect(response).to redirect_to(admin_verification_path(scheduled))
      expect(flash[:alert]).to include("only for an attempt that passed, failed or was escalated")
      expect(BreakGlassRecord.count).to eq(0)
    end

    it "opens the image only after two key holders approve, and writes the notices" do
      record = request_and_approve
      expect(record).to be_granted

      sign_in_via_magic_link(verifier)
      post image_admin_break_glass_record_path(record)

      expect(viewer_image).to eq(image)
      expect(response.parsed_body["watermark"]).to include("pId" => verifier.p_id, "subjectId" => record.public_id)
      expect_secure_image_headers
      expect(record.decryptions.sole.notices.pluck(:recipient_kind)).to include("key_holder", "member")
    end

    it "refuses the image to a key holder who did not ask" do
      record = request_and_approve

      post image_admin_break_glass_record_path(record)

      expect(response).to have_http_status(:forbidden)
      expect(BreakGlassDecryption.count).to eq(0)
    end

    it "lets a team member delay the member notice with a reason" do
      record = request_and_approve
      sign_in_via_magic_link(verifier)
      post image_admin_break_glass_record_path(record)
      notice = BreakGlassNotice.find_by!(recipient_kind: "member")

      patch delay_admin_break_glass_notice_path(notice), params: { reason: "Active fraud case 12" }

      expect(notice.reload).to be_delayed
      get admin_break_glass_records_path
      expect(response.body).to include("Active fraud case 12", "Not signed off yet", "Lift the delay")
      expect(response.body).not_to include(sign_off_delay_admin_break_glass_notice_path(notice))

      other = create(:user, :identity_team, :verified)
      sign_in_via_magic_link(other)
      patch sign_off_delay_admin_break_glass_notice_path(notice)
      expect(notice.reload).not_to be_delay_signed_off

      second = create(:user, :owner, :verified)
      sign_in_via_magic_link(second)
      patch sign_off_delay_admin_break_glass_notice_path(notice)

      expect(notice.reload).to have_attributes(delay_signed_off_by: second)
      expect(flash[:notice]).to include("at the latest")
    end

    it "shows the board report to a board member" do
      record = request_and_approve
      sign_in_via_magic_link(verifier)
      post image_admin_break_glass_record_path(record)
      sign_in_via_magic_link(create(:user, :admin, :verified, is_board: true))

      get admin_break_glass_report_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(record.public_id, "Fraud report: compare the document.")
    end

    it "keeps the board report from other admins" do
      sign_in_via_magic_link(create(:user, :admin, :verified))

      get admin_break_glass_report_path

      expect(response).to redirect_to(admin_root_path)
    end
  end

  describe "identity team roles" do
    let(:owner) { create(:user, :owner, :verified) }
    let(:target) { create(:user, :admin, :verified) }

    it "lets an owner add a key holder, which also adds the system group" do
      sign_in_via_magic_link(owner)

      patch admin_user_identity_team_path(target), params: { identity_team: "1", identity_key_holder: "1" }

      expect(target.reload).to have_attributes(identity_team: true, identity_key_holder: true, identity_lead: false)
      expect(target.groups.pluck(:slug)).to include("identity-team")
    end

    it "does not let an owner change their own role" do
      sign_in_via_magic_link(owner)

      patch admin_user_identity_team_path(owner), params: { identity_team: "1", identity_key_holder: "1" }

      expect(owner.reload.identity_key_holder).to be(false)
    end

    it "does not let a superadmin change it" do
      sign_in_via_magic_link(create(:user, :superadmin, :verified))

      patch admin_user_identity_team_path(target), params: { identity_team: "1" }

      expect(target.reload.identity_team).to be(false)
    end

    it "shows the verification status on the admin user page" do
      sign_in_via_magic_link(owner)

      get admin_user_path(member)

      expect(response.body).to include("Identity verification", "Change the identity team role")
    end
  end

  describe "the app gate" do
    let(:application) { Doorkeeper::Application.create!(name: "Ganymede", redirect_uri: "https://ganymede.example.com/cb") }

    it "lets a superadmin require verification for an app" do
      sign_in_via_magic_link(create(:user, :superadmin, :verified))

      expect { patch verification_admin_oauth_application_path(application), params: { required: true } }
        .to have_enqueued_job(RevokeLostAppAccessJob)
      expect(application.reload.requires_verification).to be(true)
    end

    it "does not let an admin change it" do
      sign_in_via_magic_link(create(:user, :admin, :verified))

      patch verification_admin_oauth_application_path(application), params: { required: true }

      expect(application.reload.requires_verification).to be(false)
    end
  end
end
