# frozen_string_literal: true

require "rails_helper"

# The identity team's pages (/identity): queue, pre-review, call outcome,
# escalations and break-glass, plus the board report in the admin panel.
RSpec.describe "Identity verification pages", type: :request do
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
    # The end of pre-review seals the image (see IdDocumentVault).
    before { active_key_set_without_holders }

    it "turns away an admin who is not on the identity team" do
      sign_in_via_magic_link(create(:user, :admin, :verified))

      get identity_verifications_path

      expect(response).to redirect_to(root_path)
    end

    it "turns away an owner who is not on the identity team" do
      sign_in_via_magic_link(create(:user, :owner, :verified))

      get identity_break_glass_records_path

      expect(response).to redirect_to(root_path)
    end

    it "lets a verifier without the admin role in, and keeps them out of the admin panel" do
      plain_verifier = create(:user, :verified, identity_team: true)
      create(:verification, user: member)
      sign_in_via_magic_link(plain_verifier)

      get identity_verifications_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(%(href="#{admin_users_path}"))

      get identity_break_glass_records_path
      expect(response).to have_http_status(:ok)

      get admin_users_path
      expect(response).to redirect_to("/login")
      get admin_deletion_requests_path
      expect(response).to redirect_to("/login")
    end

    it "lets a verifier without the admin role take an attempt and record the call" do
      plain_verifier = create(:user, :verified, identity_team: true)
      verification = create(:verification, user: member)
      sign_in_via_magic_link(plain_verifier)

      patch start_pre_review_identity_verification_path(verification)
      patch approve_document_identity_verification_path(verification)
      patch schedule_call_identity_verification_path(verification), params: { call_scheduled_for: 2.days.from_now.strftime("%Y-%m-%dT%H:%M") }
      patch decide_identity_verification_path(verification),
            params: { outcome: "failed", reason: "Not the person on the ID.", age_consistent: "yes", region_consistent: "yes" }

      expect(verification.reload).to have_attributes(status: "failed", verifier: plain_verifier)
    end

    it "no longer serves the old admin paths" do
      sign_in_via_magic_link(verifier)

      get "/admin/verifications"

      expect(response).to redirect_to("/login")
    end

    it "shows the queue and the nav link to the identity team" do
      create(:verification, user: member)
      sign_in_via_magic_link(verifier)

      get identity_verifications_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Waiting for pre-review", "Ada", %(href="#{identity_verifications_path}"))
    end

    it "finds an attempt by its public id and not by its database id" do
      verification = create(:verification, user: member)
      sign_in_via_magic_link(verifier)

      expect(identity_verification_path(verification)).to eq("/identity/verifications/#{verification.hashid}")
      get "/identity/verifications/#{verification.id}"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "pre-review" do
    # The end of pre-review seals the image (see IdDocumentVault).
    before {
      active_key_set_without_holders
      sign_in_via_magic_link(verifier)
    }

    let(:verification) { create(:verification, user: member) }


    it "takes the attempt and gives the image to the secure viewer of the pre-reviewer, with a log row" do
      patch start_pre_review_identity_verification_path(verification)
      post image_identity_verification_path(verification)

      expect(viewer_image).to eq(image)
      expect(response.parsed_body).to include("content_type" => "image/png")
      expect(response.parsed_body["watermark"]).to include("name" => verifier.full_name, "pId" => verifier.p_id,
                                                           "subjectId" => verification.public_id)
      expect(response.parsed_body.dig("watermark", "time")).to match(/\A\d{4}-\d\d-\d\dT.*Z\z/)
      expect_secure_image_headers
      expect(verification.events.where(kind: "document_viewed").count).to eq(1)
    end

    it "shows the viewer in the page, with no image link and no new tab" do
      patch start_pre_review_identity_verification_path(verification)
      get identity_verification_path(verification)

      expect(response.body).to include('data-controller="secure-image"', image_identity_verification_path(verification))
      expect(response.body).not_to match(/<a[^>]+#{verification.hashid}[^>]*target="_blank"/)
      expect(response.body).not_to match(/<img[^>]+#{verification.hashid}/)
    end

    it "has no route that serves the raw image" do
      routes = Rails.application.routes.routes.map { |route| [route.verb, route.path.spec.to_s] }
      expect(routes.map(&:last).grep(/\/(verifications|break_glass_records)\/:id\/document/)).to be_empty
      image_routes = routes.select { |_verb, path| path.match?(/\/(verifications|break_glass_records)\/:id\/image/) }
      expect(image_routes.map(&:first).uniq).to eq(["POST"])
    end

    it "does not open the image before pre-review" do
      post image_identity_verification_path(verification)

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).not_to have_key("data")
      expect_secure_image_headers
      expect(verification.events.where(kind: "document_viewed")).to be_empty
    end

    it "asks for a new document with a note" do
      patch start_pre_review_identity_verification_path(verification)
      patch reject_document_identity_verification_path(verification), params: { note: "The photo is blurry." }

      expect(verification.reload).to be_needs_resubmission
    end

    it "marks the document OK, then records the agreed call time" do # rubocop:disable RSpec/MultipleExpectations
      patch start_pre_review_identity_verification_path(verification)
      get identity_verification_path(verification)
      expect(response.body).to include("Document OK", "Send back")

      patch approve_document_identity_verification_path(verification)
      expect(verification.reload).to be_awaiting_call
      expect(flash[:notice]).to include("email or Slack")

      get identity_verification_path(verification)
      expect(response.body).to include("Record the agreed call time")
      expect(response.body).not_to include(image_identity_verification_path(verification))
      get identity_verifications_path
      expect(response.body).to include("Document OK: agree a call time")

      patch schedule_call_identity_verification_path(verification), params: { call_scheduled_for: 2.days.from_now.strftime("%Y-%m-%dT%H:%M") }

      expect(verification.reload).to be_call_scheduled
    end

    it "lets another verifier take over the pre-review from the page" do
      patch start_pre_review_identity_verification_path(verification)
      other = create(:user, :identity_team)
      sign_in_via_magic_link(other)

      get identity_verification_path(verification)
      expect(response.body).to include("Take over pre-review")
      expect(response.body).not_to include(approve_document_identity_verification_path(verification))

      patch take_over_pre_review_identity_verification_path(verification)

      expect(verification.reload.pre_reviewer).to eq(other)
      expect(flash[:notice]).to include("hand-over is logged")
      get identity_verification_path(verification)
      expect(response.body).to include("Document OK", image_identity_verification_path(verification))
      expect(response.body).not_to include("Take over pre-review")
    end

    it "does not record a call time before the document is OK" do
      patch start_pre_review_identity_verification_path(verification)
      patch schedule_call_identity_verification_path(verification), params: { call_scheduled_for: 2.days.from_now.strftime("%Y-%m-%dT%H:%M") }

      expect(verification.reload).to be_pre_review
    end
  end

  describe "recording the call outcome" do
    let(:member) { create(:user, :verified, first_name: "Ada", legal_first_name: "Erika", legal_last_name: "Mustermann", birthday: Date.new(1990, 8, 12)) }
    let(:verification) { create(:verification, :call_scheduled, user: member) }
    let(:params) do
      {
        outcome: "verified", reason: "Face matched the ID held up on the call.", age_consistent: "yes", region_consistent: "yes",
        us_resident: "yes", us_state: "MA", residency_evidence: "id_document",
        identifiers: {
          document_type: "passport", issuing_country: "DE", document_number: "C01X00T47",
          legal_name: "Erika Mustermann", date_of_birth: "1990-08-12"
        }
      }
    end

    # The end of pre-review seals the image (see IdDocumentVault).
    before {
      active_key_set_without_holders
      sign_in_via_magic_link(verifier)
    }



    it "shows the attestation form and no recording field" do
      get identity_verification_path(verification)

      expect(response.body).to include("Consistency attestation", "Never check gender",
                                       "Weave keeps document and national ID numbers only as one-way hashes for the fraud check. " \
                                       "The name and birthday must match the member's account.")
      expect(response.body).not_to include("Mustermann", "1990-08-12")
      expect(response.body).not_to match(/name="[^"]*(video|recording)/)
    end

    it "names the identifier fields so the decision receives them" do
      get identity_verification_path(verification)

      fields = Nokogiri::HTML(response.body).css("[name^='identifiers[']").map { |field| field["name"] }
      expect(fields).to include("identifiers[document_type]", "identifiers[issuing_country]", "identifiers[document_number]",
                                "identifiers[legal_name]", "identifiers[date_of_birth]")
    end

    it "gives each attestation select one placeholder, Choose, and no empty option" do
      get identity_verification_path(verification)

      page = Nokogiri::HTML(response.body)
      %w[age_consistent region_consistent us_resident].each do |name|
        options = page.css("select[name='#{name}'] option").map { |option| [option["value"], option.text] }
        expect(options).to eq([["", "Choose"], ["yes", "Yes"], ["no", "No"]])
      end
    end

    it "records a pass and stores no identifier" do
      patch decide_identity_verification_path(verification), params: params

      expect(verification.reload).to be_verified
      expect(member.verification_status).to eq("verified")
      stored = Verification.where(id: verification.id).to_a.to_json + VerificationEvent.all.to_a.to_json +
               PaperTrail::Version.where(item_type: "Verification").to_a.to_json
      expect(stored).not_to include("C01X00T47", "Mustermann")
    end

    it "shows which field differs after a mismatch, keeps the typed entry and never shows the account value" do
      patch decide_identity_verification_path(verification),
            params: params.deep_merge(identifiers: { legal_name: "Erika Musterfrau", date_of_birth: "1990-08-13" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(verification.reload).to be_call_scheduled
      expect(response.body).to include("legal name and birthday you typed do not match",
                                       "The name does not match the account.", "The birthday does not match the account.",
                                       'value="Erika Musterfrau"', "Failed: details don&#39;t match the account")
      expect(response.body).not_to include("Mustermann", "1990-08-12")
    end

    it "fails the call for details that don't match the account" do
      patch decide_identity_verification_path(verification), params: { details_mismatch: "1", reason: "" }

      expect(verification.reload).to be_failed
      expect(verification.decision_reason).to eq(VerificationFlow::DETAILS_MISMATCH_REASON)
    end

    it "gives a key holder the outcome form" do
      sign_in_via_magic_link(create(:user, :key_holder, :verified))

      get identity_verification_path(verification)

      expect(response.body).to include(decide_identity_verification_path(verification))
    end

    it "explains a refusal" do
      patch decide_identity_verification_path(verification), params: params.merge(age_consistent: "no")

      expect(verification.reload).to be_call_scheduled
      expect(flash[:alert]).to include("Age consistent")
    end
  end

  describe "escalations" do
    it "lets the lead resolve one" do
      lead = create(:user, :identity_lead)
      verification = create(:verification, :failed, user: member, escalated_at: 1.hour.ago)
      sign_in_via_magic_link(lead)

      patch resolve_escalation_identity_verification_path(verification), params: { resolution: "retry_allowed", note: "Camera problems" }

      expect(verification.reload.escalation_resolution).to eq("retry_allowed")
    end
  end

  describe "break-glass" do
    let!(:custody) { setup_key_custody }
    let(:keys) { custody.last }
    let(:verification) { seal!(create(:verification, :verified, user: member)) }

    # Each holder approves like the browser: fetch the options, open the
    # share with the hardware key, send the share and the answer.
    def approve_as(holder, record)
      sign_in_via_magic_link(holder)
      post approval_options_identity_break_glass_record_path(record), as: :json
      options = response.parsed_body
      fake = keys[holder].first
      share = fake.open(options["wrapped"][fake.external_id])
      patch approve_identity_break_glass_record_path(record),
            params: { credential: fake.assert(options.dig("request", "challenge")), share: b64url(share) }, as: :json
      share
    end

    # The requester's browser: a one-time key pair, the reason and the
    # public key as JSON.
    def ask_for_break_glass(for_verification)
      post identity_verification_break_glass_records_path(for_verification),
           params: { reason: "Fraud report: compare the document.", requester_public_key: browser_public_key(verifier) }, as: :json
    end

    def request_and_approve
      sign_in_via_magic_link(verifier)
      ask_for_break_glass(verification)
      record = BreakGlassRecord.last
      keys.keys.first(2).each { |holder| approve_as(holder, record) }
      record.reload
    end

    it "shows the break-glass button only after a decision" do
      sign_in_via_magic_link(verifier)
      get identity_verification_path(verification)
      expect(response.body).to include("Ask for break-glass access")

      scheduled = create(:verification, :call_scheduled, user: create(:user, :verified))
      get identity_verification_path(scheduled)
      expect(response.body).not_to include("Ask for break-glass access")
    end

    it "refuses a break-glass request before the decision, with the reason" do
      scheduled = create(:verification, :awaiting_call, user: create(:user, :verified))
      sign_in_via_magic_link(verifier)

      post identity_verification_break_glass_records_path(scheduled), params: { reason: "Fraud report: compare the document." }

      expect(response).to redirect_to(identity_verification_path(scheduled))
      expect(flash[:alert]).to include("only for an attempt that passed, failed or was escalated")
      expect(BreakGlassRecord.count).to eq(0)
    end

    it "shows the approve button that runs the hardware key script" do
      sign_in_via_magic_link(verifier)
      ask_for_break_glass(verification)
      sign_in_via_magic_link(keys.keys.first)

      get identity_break_glass_records_path

      expect(response.body).to include("Approve with my hardware key", approval_options_identity_break_glass_record_path(BreakGlassRecord.last))
    end

    it "answers an approval as JSON and keeps the share out of the log" do # rubocop:disable RSpec/ExampleLength
      sign_in_via_magic_link(verifier)
      ask_for_break_glass(verification)
      record = BreakGlassRecord.last
      log = StringIO.new
      logger = ActiveSupport::Logger.new(log)
      share = nil
      original = Rails.logger
      begin
        Rails.logger = ActionController::Base.logger = logger
        share = approve_as(keys.keys.first, record)
      ensure
        Rails.logger = ActionController::Base.logger = original
      end

      expect(response.parsed_body).to include("granted" => false)
      expect(log.string).to include("approve")
      expect(log.string).not_to include(b64url(share))
      expect(log.string).not_to include("clientDataJSON")
    end

    it "refuses an approval with a wrong share as JSON" do
      sign_in_via_magic_link(verifier)
      ask_for_break_glass(verification)
      record = BreakGlassRecord.last
      holder = keys.keys.first
      sign_in_via_magic_link(holder)
      post approval_options_identity_break_glass_record_path(record), as: :json

      patch approve_identity_break_glass_record_path(record),
            params: { credential: keys[holder].first.assert(response.parsed_body.dig("request", "challenge")),
                      share: b64url(SecureRandom.random_bytes(33))
}, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("not your share")
    end

    def open_as_requester(record)
      sign_in_via_magic_link(verifier)
      post open_identity_break_glass_record_path(record), as: :json
    end

    it "takes the request as JSON with the browser's public key, and needs that key" do
      sign_in_via_magic_link(verifier)
      ask_for_break_glass(verification)

      record = BreakGlassRecord.sole
      expect(response.parsed_body).to include("id" => record.public_id, "redirect" => identity_break_glass_records_path)
      expect(record.requester_public_key).to eq(browser_public_key(verifier))

      post identity_verification_break_glass_records_path(verification), params: { reason: "Fraud report: compare the document." }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("one-time key")
    end

    it "gives the second approver no image, and the requester opens it once in the browser" do # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
      record = request_and_approve
      expect(record).to be_granted

      body = response.parsed_body
      expect(body).to include("granted" => true)
      expect(body.keys).not_to include("image")
      expect(body["message"]).to include("You do not see it")
      expect(BreakGlassDecryption.count).to eq(0)

      get identity_break_glass_records_path
      expect(response.body).not_to include(open_identity_break_glass_record_path(record))
      sign_in_via_magic_link(verifier)
      get identity_break_glass_records_path
      expect(response.body).to include("Ready for you to open", open_identity_break_glass_record_path(record), 'data-controller="break-glass"')

      open_as_requester(record)
      expect(response).to have_http_status(:ok)
      expect(open_in_browser(response.parsed_body, verifier)).to eq(image)
      expect(response.parsed_body["watermark"]).to include("pId" => verifier.p_id, "subjectId" => record.public_id)
      expect_secure_image_headers
      expect(record.decryptions.sole).to have_attributes(viewer: verifier)
      expect(record.decryptions.sole.notices.pluck(:recipient_kind)).to include("key_holder", "member")

      open_as_requester(record)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("already opened")
    end

    it "refuses the open to an approver" do
      record = request_and_approve

      post open_identity_break_glass_record_path(record), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).not_to have_key("sealed_key")
      expect(BreakGlassDecryption.count).to eq(0)
    end

    it "refuses the open after the handoff window" do
      record = request_and_approve

      travel(VerificationSettings.break_glass_handoff_ttl + 1.minute) { open_as_requester(record) }

      expect(response.parsed_body["error"]).to include("Ask again")
    end

    it "has no route that opens a granted image again" do
      record = request_and_approve
      open_as_requester(record)

      expect { Rails.application.routes.recognize_path("/identity/break_glass_records/#{record.to_param}/document") }
        .to raise_error(ActionController::RoutingError)
      expect(BreakGlassDecryption.count).to eq(1)
    end

    it "issues approval options only on POST" do
      sign_in_via_magic_link(verifier)
      ask_for_break_glass(verification)

      path = approval_options_identity_break_glass_record_path(BreakGlassRecord.last)
      expect { Rails.application.routes.recognize_path(path, method: :get) }.to raise_error(ActionController::RoutingError)
      expect(Rails.application.routes.recognize_path(path, method: :post)).to include(action: "approval_options")
    end

    it "lets a team member delay the member notice with a reason" do # rubocop:disable RSpec/ExampleLength
      open_as_requester(request_and_approve)
      sign_in_via_magic_link(verifier)
      notice = BreakGlassNotice.find_by!(recipient_kind: "member")

      patch delay_identity_break_glass_notice_path(notice), params: { reason: "Active fraud case 12" }

      expect(notice.reload).to be_delayed
      get identity_break_glass_records_path
      expect(response.body).to include("Active fraud case 12", "Not signed off yet", "Lift the delay")
      expect(response.body).not_to include(sign_off_delay_identity_break_glass_notice_path(notice))

      other = create(:user, :identity_team, :verified)
      sign_in_via_magic_link(other)
      patch sign_off_delay_identity_break_glass_notice_path(notice)
      expect(notice.reload).not_to be_delay_signed_off

      second = create(:user, :owner, :verified)
      sign_in_via_magic_link(second)
      patch sign_off_delay_identity_break_glass_notice_path(notice)

      expect(notice.reload).to have_attributes(delay_signed_off_by: second)
      expect(flash[:notice]).to include("at the latest")
    end

    it "shows the board report to a board member" do
      record = request_and_approve
      open_as_requester(record)
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

  describe "the admin user page" do
    it "shows the verification status and links to the governance page" do
      sign_in_via_magic_link(create(:user, :owner, :verified))

      get admin_user_path(member)

      expect(response.body).to include("Identity verification", identity_governance_path)
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
