# frozen_string_literal: true

require "rails_helper"

RSpec.describe Oauth::DiscoveryController, type: :controller do
  describe "GET #oauth_authorization_server" do
    before do
      get :oauth_authorization_server
    end

    it "returns http success" do
      expect(response).to have_http_status(:success)
    end

    it "returns JSON content type" do
      expect(response.content_type).to include("application/json")
    end

    it "includes required OAuth 2.0 metadata fields" do
      json = JSON.parse(response.body)

      # Required fields per RFC 8414
      expect(json).to include("issuer")
      expect(json).to include("authorization_endpoint")
      expect(json).to include("token_endpoint")
      expect(json).to include("response_types_supported")
      expect(json).to include("grant_types_supported")
      expect(json).to include("scopes_supported")
    end

    it "includes correct endpoint URLs" do
      json = JSON.parse(response.body)
      base_url = "#{request.protocol}#{request.host_with_port}"

      expect(json["issuer"]).to eq(base_url)
      expect(json["authorization_endpoint"]).to eq("#{base_url}/oauth/authorize")
      expect(json["token_endpoint"]).to eq("#{base_url}/oauth/token")
      expect(json["revocation_endpoint"]).to eq("#{base_url}/oauth/revoke")
      expect(json["introspection_endpoint"]).to eq("#{base_url}/oauth/introspect")
      expect(json["userinfo_endpoint"]).to eq("#{base_url}/oauth/userinfo")
    end

    it "includes supported grant types" do
      json = JSON.parse(response.body)

      expect(json["grant_types_supported"]).to include("authorization_code")
      expect(json["grant_types_supported"]).to include("client_credentials")
      expect(json["grant_types_supported"]).to include("refresh_token")
    end

    it "includes supported response types" do
      json = JSON.parse(response.body)

      expect(json["response_types_supported"]).to include("code")
      expect(json["response_types_supported"]).to include("token")
    end

    it "includes supported scopes" do
      json = JSON.parse(response.body)

      expect(json["scopes_supported"]).to include("profile")
      expect(json["scopes_supported"]).to include("email")
      expect(json["scopes_supported"]).to include("phone")
      expect(json["scopes_supported"]).to include("admin")
    end

    it "includes PKCE support" do
      json = JSON.parse(response.body)

      expect(json["code_challenge_methods_supported"]).to include("S256")
      expect(json["code_challenge_methods_supported"]).to include("plain")
    end

    it "includes token endpoint authentication methods" do
      json = JSON.parse(response.body)

      expect(json["token_endpoint_auth_methods_supported"]).to include("client_secret_basic")
      expect(json["token_endpoint_auth_methods_supported"]).to include("client_secret_post")
    end
  end

  describe "GET #openid_configuration" do
    before do
      get :openid_configuration
    end

    it "returns http success" do
      expect(response).to have_http_status(:success)
    end

    it "returns JSON content type" do
      expect(response.content_type).to include("application/json")
    end

    it "includes OpenID Connect specific fields" do
      json = JSON.parse(response.body)

      expect(json).to include("subject_types_supported")
      expect(json).to include("id_token_signing_alg_values_supported")
      expect(json).to include("claims_supported")
    end

    it "includes supported claims" do
      json = JSON.parse(response.body)

      expect(json["claims_supported"]).to include("sub")
      expect(json["claims_supported"]).to include("name")
      expect(json["claims_supported"]).to include("email")
      expect(json["claims_supported"]).to include("email_verified")
      expect(json["claims_supported"]).to include("phone_number")
      expect(json["claims_supported"]).to include("phone_number_verified")
    end

    it "includes phone scope" do
      json = JSON.parse(response.body)

      expect(json["scopes_supported"]).to include("phone")
    end

    it "includes openid scope" do
      json = JSON.parse(response.body)

      expect(json["scopes_supported"]).to include("openid")
    end
  end
end
