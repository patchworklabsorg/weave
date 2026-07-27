# frozen_string_literal: true

require "rails_helper"

# Regression coverage for a lockout that had no template behind it.
#
# EmailConfirmationsController#show has always been the destination
# ApplicationController#authenticate_user! sends unconfirmed users to, but
# app/views/email_confirmations/ never existed. Rails answers a missing template
# with 406 Not Acceptable, so signing in with an unconfirmed account bounced
# every request to a page that itself 406'd — a closed loop with no way out and
# no error anyone could act on. 58 of 59 accounts were in that state.
RSpec.describe "Email confirmations", type: :request do
  let(:user) { create(:user, :unverified) }

  def login(user)
    token = SecureRandom.urlsafe_base64(32)
    user.update!(
      magic_link_token: token,
      magic_link_expires_at: 15.minutes.from_now,
      magic_link_used_at: nil
    )
    get magic_link_login_path(token: token)
  end

  describe "GET /email_confirmation" do
    before { login(user) }

    it "renders the confirmation page rather than 406ing" do
      get email_confirmation_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Confirm your email")
      expect(response.body).to include(user.email)
    end

    it "offers a way to resend, so the page is not a dead end" do
      user.update!(confirmation_sent_at: 1.hour.ago)

      get email_confirmation_path

      expect(response.body).to include("Resend confirmation email")
      expect(response.body).to include(resend_email_confirmation_path)
    end

    it "says to wait instead of offering a resend that would be rate limited" do
      user.update!(confirmation_sent_at: Time.current)

      get email_confirmation_path

      expect(response.body).not_to include("Resend confirmation email")
      expect(response.body).to include("in a few minutes")
    end

    it "sends an already-confirmed user on to the app" do
      user.verify_email

      get email_confirmation_path

      expect(response).to redirect_to(root_path)
    end
  end

  # The turbo_stream branch of #resend replaces the "resend_section" node by id,
  # which only works if the partial's outermost element carries it.
  describe "POST /email_confirmation/resend" do
    before do
      login(user)
      user.update!(confirmation_sent_at: 1.hour.ago)
    end

    it "renders a replaceable resend_section for a turbo_stream request" do
      post resend_email_confirmation_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("resend_section")
    end

    it "redirects back to the confirmation page for a plain request" do
      post resend_email_confirmation_path

      expect(response).to redirect_to(email_confirmation_path)
    end
  end
end
