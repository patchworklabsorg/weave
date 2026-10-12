# frozen_string_literal: true

require "rails_helper"

# A member under 18 asks a parent or guardian for consent from /slack, and the
# guardian answers from the link in the email.
RSpec.describe "Guardian consent", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user, :verified, :minor, first_name: "Ada") }

  describe "the member's side" do
    before { sign_in_via_magic_link(user) }

    it "shows the consent step before the Slack invite" do
      get slack_onboarding_path

      expect(response.body).to include("Get consent from a parent or guardian", "Their email address")
      expect(user.slack_onboarding_step).to eq(:guardian_consent)
    end

    it "does not show the step to an adult" do
      adult = create(:user, :verified)
      sign_in_via_magic_link(adult)

      get slack_onboarding_path

      expect(response.body).not_to include("Get consent from a parent or guardian")
    end

    it "sends the request to the guardian" do
      expect do
        post guardian_consent_request_path, params: { guardian_name: "Grace Hopper", guardian_email: "grace@example.org" }
      end.to have_enqueued_mail(GuardianConsentMailer, :request_consent)

      expect(response).to redirect_to(slack_onboarding_path)
      follow_redirect!
      expect(response.body).to include("We sent a request to grace@example.org")
    end

    it "shows the errors next to the fields" do
      post guardian_consent_request_path, params: { guardian_name: "", guardian_email: user.email }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("belongs to a Weave account")
    end

    it "sends the request again only after the cooldown" do
      consent = create(:guardian_consent, user:, sent_at: 1.minute.ago)

      post resend_guardian_consent_request_path
      expect(flash[:alert]).to be_present

      consent.update!(sent_at: 1.hour.ago)
      expect { post resend_guardian_consent_request_path }.to have_enqueued_mail(GuardianConsentMailer, :request_consent)
      expect(consent.reload.sent_at).to be > 1.minute.ago
    end

    it "sends a member who does not need consent back to /slack" do
      create(:guardian_consent, :granted, user:)

      post guardian_consent_request_path, params: { guardian_name: "Grace Hopper", guardian_email: "grace@example.org" }

      expect(response).to redirect_to(slack_onboarding_path)
      expect(user.guardian_consents.count).to eq(1)
    end
  end

  describe "the guardian's side" do
    let(:token) { SecureRandom.urlsafe_base64(32) }
    let!(:consent) { create(:guardian_consent, user:, raw_token: token) }

    it "explains Patchwork Labs and asks for consent" do
      get guardian_consent_path(token:)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Consent for Ada to join Patchwork Labs", "I give consent")
    end

    it "tells the guardian who the members are and what the consent records" do
      get guardian_consent_path(token:)

      expect(response.body).to include("some members are adults", "an identifier for your device",
                                       "Before Ada can get a budget",
                                       "1 year after the account is deleted", "https://patchworklabs.org/privacy")
    end

    it "answers 404 for an unknown token" do
      get guardian_consent_path(token: "nope")

      expect(response).to have_http_status(:not_found)
      expect(response.body).to include("This link does not work")
    end

    it "records the consent and starts the Slack invite" do
      expect do
        post guardian_consent_path(token:), params: { confirm: "1", signed_name: "Grace Hopper" }
      end.to have_enqueued_job(InviteToSlackJob).with(user.id)
                                                .and have_enqueued_mail(GuardianConsentMailer, :receipt)
        .and have_enqueued_mail(GuardianConsentMailer, :granted)

      expect(consent.reload).to be_granted
      expect(user.reload.guardian_consent_missing?).to be(false)
      follow_redirect!
      expect(response.body).to include("Take back my consent")
    end

    it "needs the box and a typed name" do
      post guardian_consent_path(token:), params: { signed_name: " " }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Confirm that you are the parent", "Type your full name.")
      expect(consent.reload).to be_pending
    end

    it "does not let the member consent for themselves" do
      sign_in_via_magic_link(user)

      post guardian_consent_path(token:), params: { confirm: "1", signed_name: "Grace Hopper" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(consent.reload).to be_pending
    end

    it "refuses an expired link" do
      consent.update!(expires_at: 1.minute.ago)

      post guardian_consent_path(token:), params: { confirm: "1", signed_name: "Grace Hopper" }

      expect(response.body).to include("This link has expired")
      expect(consent.reload).to be_pending
    end

    it "refuses a link that a newer request replaced" do
      GuardianConsent.issue!(user, guardian_name: "Alan Turing", guardian_email: "alan@example.org")

      get guardian_consent_path(token:)

      expect(response.body).to include("This link does not work")
    end

    it "lets the guardian take the consent back" do
      consent.record_grant!(signed_name: "Grace Hopper", ip: nil, user_agent: nil)

      expect do
        delete guardian_consent_path(token:)
      end.to have_enqueued_job(RevokeLostAppAccessJob).with(user_id: user.id)
                                                      .and have_enqueued_mail(GuardianConsentMailer, :revoked)
        .and have_enqueued_mail(AdminMailer, :guardian_consent_revoked)

      expect(consent.reload).to be_revoked
      expect(user.reload.guardian_consent_missing?).to be(true)
      follow_redirect!
      expect(response.body).to include("Consent taken back")
    end
  end
end
