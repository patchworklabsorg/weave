# frozen_string_literal: true

require "rails_helper"

# A resource server such as Quilt gets an app's client_credentials token on
# each request and checks it at introspection. Doorkeeper lets an app
# introspect only its own tokens, so an app allowed the `introspect` scope may
# also introspect app tokens of other apps. A user's token stays private to the
# app it was issued to.
RSpec.describe "OAuth token introspection", type: :request do
  let(:quilt) do
    Doorkeeper::Application.create!(name: "Quilt", redirect_uri: "https://quilt.example.com/cb", scopes: "introspect")
  end
  let(:krater) do
    Doorkeeper::Application.create!(name: "Krater", redirect_uri: "https://krater.example.com/cb",
                                    scopes: "openid profile quilt")
  end
  let(:user) { create(:user, :verified, :accepted_code_of_conduct) }

  def basic_auth(app)
    { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(app.uid, app.plaintext_secret) }
  end

  def client_credentials_token(app, scope:)
    post oauth_token_path, params: { grant_type: "client_credentials", scope: scope }, headers: basic_auth(app)
    expect(response).to have_http_status(:ok)
    response.parsed_body.fetch("access_token")
  end

  def introspect(token, as:)
    post oauth_introspect_path, params: { token: token }, headers: basic_auth(as)
    response.parsed_body
  end

  describe "an app allowed the introspect scope" do
    it "sees another app's client_credentials token as active, with its client and scope" do
      token = client_credentials_token(krater, scope: "quilt")

      freeze_time do
        record = Doorkeeper::AccessToken.by_token(token)
        body = introspect(token, as: quilt)

        expect(response).to have_http_status(:ok)
        expect(body).to include(
          "active"     => true,
          "client_id"  => krater.uid,
          "scope"      => "quilt",
          "token_type" => "Bearer",
          "exp"        => record.expires_at.to_i,
          "iat"        => record.created_at.to_i
        )
      end
    end

    it "does not see a user's token of another app" do
      token = Doorkeeper::AccessToken.create!(application: krater, resource_owner_id: user.id, scopes: "openid profile")

      expect(introspect(token.plaintext_token, as: quilt)).to eq("active" => false)
    end

    it "sees a revoked token as inactive" do
      token = client_credentials_token(krater, scope: "quilt")
      Doorkeeper::AccessToken.by_token(token).revoke

      expect(introspect(token, as: quilt)).to eq("active" => false)
    end

    it "sees an expired token as inactive" do
      token = client_credentials_token(krater, scope: "quilt")

      travel(Doorkeeper.config.access_token_expires_in + 1.minute) do
        expect(introspect(token, as: quilt)).to eq("active" => false)
      end
    end

    it "can't use a bearer token to introspect another app's token" do
      token = client_credentials_token(krater, scope: "quilt")
      quilt_token = client_credentials_token(quilt, scope: "introspect")

      post oauth_introspect_path, params: { token: token }, headers: { "Authorization" => "Bearer #{quilt_token}" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "an app not allowed the introspect scope" do
    let(:other) do
      Doorkeeper::Application.create!(name: "Other", redirect_uri: "https://other.example.com/cb", scopes: "profile quilt")
    end

    it "does not see another app's client_credentials token" do
      token = client_credentials_token(krater, scope: "quilt")

      expect(introspect(token, as: other)).to eq("active" => false)
    end

    it "still sees its own tokens, as Doorkeeper's default allows" do
      app_token = client_credentials_token(krater, scope: "quilt")
      user_token = Doorkeeper::AccessToken.create!(application: krater, resource_owner_id: user.id, scopes: "profile")

      expect(introspect(app_token, as: krater)).to include("active" => true, "client_id" => krater.uid)
      expect(introspect(user_token.plaintext_token, as: krater)).to include("active" => true, "client_id" => krater.uid)
    end
  end

  describe "app scopes" do
    it "are not issued to an app that is not allowed them" do
      post oauth_token_path, params: { grant_type: "client_credentials", scope: "quilt" }, headers: basic_auth(quilt)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("invalid_scope")
    end

    %w[quilt introspect directory].each do |scope|
      it "can't be asked for at the authorization endpoint (#{scope})" do
        app = Doorkeeper::Application.create!(name: "Client", redirect_uri: "https://client.example.com/cb",
                                              scopes: "openid profile #{scope}")
        verifier = SecureRandom.urlsafe_base64(64)
        sign_in_via_magic_link(user)

        params = {
          client_id: app.uid, redirect_uri: app.redirect_uri, response_type: "code", scope: "openid #{scope}",
          code_challenge: Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(verifier), padding: false),
          code_challenge_method: "S256"
        }

        # The consent screen shows Weave's error page. A consent POST sends the
        # error back to the client. Neither one issues a code.
        get oauth_authorization_path, params: params
        expect(response).to have_http_status(:bad_request)
        expect(response.body).to include("The requested scope is invalid")

        post oauth_authorization_path, params: params
        expect(Rack::Utils.parse_query(URI.parse(response.location).query)).to include("error" => "invalid_scope")
        expect(Doorkeeper::AccessGrant.where(application: app)).to be_empty
      end
    end
  end
end
