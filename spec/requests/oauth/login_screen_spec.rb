# frozen_string_literal: true

require "rails_helper"

# Coverage for the sign-in screen an OAuth client's users are sent to.
#
# It used to be a dedicated form that asked for a password and marked the field
# required. Password sign-in is admin-only (AuthController#login turns everyone
# else away), so the screen could not be completed by almost anyone it was shown
# to. It now renders the same magic-link screen as /login.
#
# Magic links change what "sign in" means for the resume: the user leaves for an
# email client and comes back on a fresh request. Unless the authorize request
# itself is remembered, that return lands on the dashboard and the client waits
# for a callback that never arrives.
RSpec.describe "OAuth login screen", type: :request do
  let(:user) { create(:user, :verified) }

  let(:application) do
    Doorkeeper::Application.create!(
      name: "Test Client",
      redirect_uri: "https://client.example.com/callback",
      scopes: "openid profile email",
      confidential: false
    )
  end

  let(:code_verifier) { SecureRandom.urlsafe_base64(64) }

  def authorization_params(**overrides)
    {
      client_id: application.uid,
      redirect_uri: application.redirect_uri,
      response_type: "code",
      scope: "openid email",
      code_challenge: Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(code_verifier), padding: false),
      code_challenge_method: "S256",
      nonce: "login-nonce-123"
    }.merge(overrides)
  end

  # Compare the destination by path and params rather than by string: the resumed
  # URL is the original request's fullpath, whose query order is the browser's,
  # not the one a route helper would produce.
  def redirect_target(response)
    uri = URI.parse(response.location)
    [uri.path, Rack::Utils.parse_query(uri.query)]
  end

  def authorization_target
    [oauth_authorization_path, authorization_params.transform_keys(&:to_s)]
  end

  describe "GET /oauth/login" do
    before { get oauth_authorization_path, params: authorization_params }

    it "sends an unauthenticated visitor here rather than rendering consent" do
      expect(response).to redirect_to("/oauth/login?client_id=#{application.uid}")
    end

    it "asks for an email and a magic link, not a password" do
      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Send magic link")
      expect(Nokogiri::HTML(response.body).at_css("input[type='password']")).to be_nil
    end

    it "names the client so the visitor knows what they are signing in to" do
      follow_redirect!

      expect(response.body).to include(application.name)
      expect(response.body).to include("a central account")
    end
  end

  describe "returning from a magic link" do
    it "resumes the authorize request the visitor was sent here from" do
      get oauth_authorization_path, params: authorization_params
      follow_redirect!

      sign_in_via_magic_link(user)

      expect(redirect_target(response)).to eq(authorization_target)
    end

    it "shows consent once the resumed request is followed" do
      get oauth_authorization_path, params: authorization_params
      sign_in_via_magic_link(user)
      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Authorization required")
      expect(response.body).to include(application.name)
    end

    # The account most people arrive with was created by import and has no
    # confirmation behind it. Following the magic link confirms the address, so
    # the authorize request goes through instead of stalling behind a second
    # email the client would never wait for.
    it "carries an unconfirmed account through to consent" do
      unconfirmed = create(:user, :unverified)

      get oauth_authorization_path, params: authorization_params
      sign_in_via_magic_link(unconfirmed)
      follow_redirect!

      expect(unconfirmed.reload).to be_email_verified
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Authorization required")
    end

    # The stored path is handed straight to redirect_to, so anything that is not
    # a local authorize request is dropped rather than followed.
    it "lands on the dashboard when no authorize request is pending" do
      sign_in_via_magic_link(user)

      expect(response).to redirect_to(root_path)
    end

    it "does not resume the same authorize request twice" do
      get oauth_authorization_path, params: authorization_params
      sign_in_via_magic_link(user)
      expect(redirect_target(response)).to eq(authorization_target)

      sign_in_via_magic_link(user)

      expect(response).to redirect_to(root_path)
    end
  end
end
