# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Passkey sign-in", type: :request do
  let(:user) { create(:user, :verified) }
  let(:client) { fake_passkey_client }
  let!(:passkey) { register_passkey(user, client: client) }

  def sign_in_options
    post passkey_sign_in_options_path, as: :json
    response.parsed_body
  end

  def sign_in_with_passkey(as: user)
    challenge = sign_in_options.fetch("challenge")
    post passkey_sign_in_path, params: { credential: passkey_assertion(client, challenge, user: as) }
  end

  describe "POST /auth/passkey/options" do
    it "asks for any passkey with user verification" do
      options = sign_in_options

      expect(response).to have_http_status(:ok)
      expect(options["challenge"]).to be_present
      expect(options["userVerification"]).to eq("required")
      expect(options["allowCredentials"]).to be_blank
    end
  end

  describe "POST /auth/passkey" do
    it "signs the user in and backs the login with a session row" do
      expect { sign_in_with_passkey }.to change { user.user_sessions.count }.by(1)

      expect(response).to redirect_to(root_path)
      expect(session[:user_id]).to eq(user.id)
    end

    it "uses each challenge only once" do
      challenge = sign_in_options.fetch("challenge")
      credential = passkey_assertion(client, challenge, user: user)
      post passkey_sign_in_path, params: { credential: credential }
      delete logout_path

      post passkey_sign_in_path, params: { credential: credential }

      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to match(/timed out/)
      expect(session[:user_id]).to be_nil
    end

    it "refuses a challenge older than five minutes" do
      challenge = sign_in_options.fetch("challenge")

      travel 6.minutes do
        post passkey_sign_in_path, params: { credential: passkey_assertion(client, challenge, user: user) }
      end

      expect(response).to redirect_to(login_path)
      expect(session[:user_id]).to be_nil
    end

    it "refuses a passkey that was removed" do
      passkey.destroy!

      sign_in_with_passkey

      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to match(/isn't set up for Weave/)
      expect(session[:user_id]).to be_nil
    end

    it "refuses a locked account" do
      user.update_column(:locked_at, Time.current) # rubocop:disable Rails/SkipsModelValidations

      expect { sign_in_with_passkey }.not_to(change(User::Session, :count))

      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to match(/can't sign in right now/)
    end

    it "refuses input that is not a credential" do
      sign_in_options
      post passkey_sign_in_path, params: { credential: "garbage" }

      expect(response).to redirect_to(login_path)
      expect(session[:user_id]).to be_nil
    end

    it "returns to a pending OAuth authorization" do
      application = Doorkeeper::Application.create!(name: "Client", redirect_uri: "https://client.example.com/callback", scopes: "profile")
      get oauth_authorization_path, params: { client_id: application.uid, redirect_uri: application.redirect_uri, response_type: "code", scope: "profile" }
      return_to = session[:oauth_return_to]
      expect(return_to).to start_with("/oauth/authorize")

      sign_in_with_passkey

      expect(response).to redirect_to(return_to)
    end
  end

  describe "the login page" do
    it "offers passkeys as autofill on the email field" do
      get login_path

      expect(response.body).to include('autocomplete="username webauthn"')
      expect(response.body).to include(passkey_sign_in_path)
    end

    it "shows the passkey button" do
      get login_path

      expect(response.body).to include("Sign in with a passkey")
    end
  end
end
