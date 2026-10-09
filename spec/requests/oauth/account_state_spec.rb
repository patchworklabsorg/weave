# frozen_string_literal: true

require "rails_helper"

# An account that can't sign in to Weave must not be able to sign in anywhere
# else through Weave either. Doorkeeper's controllers don't inherit from
# ApplicationController, so its resource_owner_authenticator used to have its
# own check, which only looked at email verification: a locked, suspended or
# deactivated user with a browser cookie could still complete an OAuth sign-in
# to every client, and their refresh tokens kept minting access tokens forever.
RSpec.describe "OAuth access for accounts that can no longer sign in", type: :request do
  let(:user) { create(:user, :verified, :accepted_code_of_conduct) }
  let(:redirect_uri) { "https://client.example.com/callback" }
  let(:code_verifier) { SecureRandom.urlsafe_base64(64) }

  let(:application) do
    Doorkeeper::Application.create!(
      name: "Test Client",
      redirect_uri: redirect_uri,
      scopes: "openid profile email",
      confidential: false
    )
  end

  def authorization_params
    {
      client_id: application.uid,
      redirect_uri: redirect_uri,
      response_type: "code",
      scope: "openid profile",
      code_challenge: Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(code_verifier), padding: false),
      code_challenge_method: "S256"
    }
  end

  # Granting consent: a POST that answers with a redirect carrying the code.
  def authorization_code
    post oauth_authorization_path, params: authorization_params
    expect(response).to have_http_status(:found)
    Rack::Utils.parse_query(URI.parse(response.location).query).fetch("code")
  end

  def exchange(code)
    post oauth_token_path, params: {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: redirect_uri,
      client_id: application.uid,
      code_verifier: code_verifier
    }
    response.parsed_body
  end

  def refresh(refresh_token)
    post oauth_token_path, params: {
      grant_type: "refresh_token",
      refresh_token: refresh_token,
      client_id: application.uid
    }
    response.parsed_body
  end

  def userinfo_status(access_token)
    get oauth_userinfo_path, headers: { "Authorization" => "Bearer #{access_token}" }
    response.status
  end

  def obtain_tokens
    sign_in_via_magic_link(user)
    exchange(authorization_code)
  end

  describe "the authorization endpoint" do
    it "issues a code to an active, signed-in user" do
      sign_in_via_magic_link(user)

      get oauth_authorization_path, params: authorization_params

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Authorization required")
    end

    {
      "locked"      => ->(user) { user.lock! },
      "suspended"   => ->(user) { user.suspend! },
      "deactivated" => ->(user) { user.deactivate! }
    }.each do |state, change|
      it "sends a #{state} user with a live cookie to sign in instead of issuing a code" do
        sign_in_via_magic_link(user)
        change.call(user)

        get oauth_authorization_path, params: authorization_params

        expect(response).to redirect_to("/oauth/login?client_id=#{application.uid}")
      end
    end

    it "does not accept a session that was signed out elsewhere" do
      sign_in_via_magic_link(user)
      user.user_sessions.update_all(signed_out_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      get oauth_authorization_path, params: authorization_params

      expect(response).to redirect_to("/oauth/login?client_id=#{application.uid}")
    end

    it "does not accept an expired session" do
      sign_in_via_magic_link(user)
      user.user_sessions.update_all(expiration_at: 1.hour.ago) # rubocop:disable Rails/SkipsModelValidations

      get oauth_authorization_path, params: authorization_params

      expect(response).to redirect_to("/oauth/login?client_id=#{application.uid}")
    end

    # The stale cookie is reset before the OAuth context is stored in it. If it
    # weren't, the sign-in page would reset it on first sight and the context
    # would go with it, so signing back in would land on the dashboard.
    it "still resumes the authorize request after the user signs back in" do
      sign_in_via_magic_link(user)
      user.user_sessions.update_all(signed_out_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

      get oauth_authorization_path, params: authorization_params
      follow_redirect!
      sign_in_via_magic_link(user)

      expect(URI.parse(response.location).path).to eq(oauth_authorization_path)
    end
  end

  describe "tokens already issued" do
    {
      "locked"      => ->(user) { user.lock! },
      "suspended"   => ->(user) { user.suspend! },
      "deactivated" => ->(user) { user.deactivate! }
    }.each do |state, change|
      context "when the user is #{state}" do
        it "stops the access token working at userinfo" do
          tokens = obtain_tokens
          expect(userinfo_status(tokens["access_token"])).to eq(200)

          change.call(user)

          expect(userinfo_status(tokens["access_token"])).to eq(401)
        end

        it "stops the refresh token minting new access tokens" do
          tokens = obtain_tokens

          change.call(user)
          body = refresh(tokens["refresh_token"])

          expect(body).not_to include("access_token")
          expect(body["error"]).to eq("invalid_grant")
        end

        it "stops an unredeemed authorization code from being exchanged" do
          sign_in_via_magic_link(user)
          code = authorization_code

          change.call(user)
          body = exchange(code)

          expect(body).not_to include("access_token")
          expect(body["error"]).to eq("invalid_grant")
        end
      end
    end

    it "keeps working for an active user (refresh still succeeds)" do
      tokens = obtain_tokens

      body = refresh(tokens["refresh_token"])

      expect(body).to include("access_token", "refresh_token")
    end

    # Model callbacks do the revoking, so a change that skips them (a console
    # update_columns, a bulk update) would leave tokens alive. The token and
    # userinfo endpoints check the account themselves as a backstop.
    context "when the account was disabled without callbacks running" do
      let!(:tokens) { obtain_tokens }

      it "refuses userinfo" do
        user.update_columns(locked_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

        expect(userinfo_status(tokens["access_token"])).to eq(401)
        expect(response.headers["WWW-Authenticate"]).to include('error="invalid_token"')
      end

      it "refuses to refresh, and doesn't leave a usable token behind" do
        user.update_columns(status: "suspended") # rubocop:disable Rails/SkipsModelValidations
        existing_ids = Doorkeeper::AccessToken.pluck(:id)

        body = refresh(tokens["refresh_token"])

        expect(body["error"]).to eq("invalid_grant")
        expect(Doorkeeper::AccessToken.where.not(id: existing_ids).where(revoked_at: nil)).to be_empty
      end
    end
  end
end
