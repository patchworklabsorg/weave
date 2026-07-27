# frozen_string_literal: true

require "rails_helper"

# Regression coverage for the bug this endpoint used to have: the discovery
# documents were hand-maintained and advertised capabilities the server did not
# possess (an `openid` scope that was never registered with Doorkeeper, and
# RS256 id_tokens that nothing could issue). Every assertion here compares the
# published metadata against live configuration rather than a literal, so the
# document cannot drift back out of sync.
RSpec.describe "OAuth/OIDC discovery", type: :request do
  let(:json) { response.parsed_body }

  shared_examples "a discovery document grounded in real configuration" do
    it "advertises exactly the scopes Doorkeeper has registered" do
      expect(json["scopes_supported"]).to match_array(Doorkeeper.config.scopes.to_a)
    end

    it "advertises the openid scope, and that scope is actually requestable" do
      expect(json["scopes_supported"]).to include("openid")
      expect(Doorkeeper.config.scopes.to_a).to include("openid")
    end

    it "does not advertise a grant type that is not enabled" do
      expect(json["grant_types_supported"]).to match_array(
        Doorkeeper.config.grant_flows + ["refresh_token"]
      )
    end

    it "does not advertise a response type that is not enabled" do
      expect(json["response_types_supported"]).to match_array(
        Doorkeeper.config.authorization_response_types
      )
      # The implicit flow is off, so `token` must not appear. It used to.
      expect(json["response_types_supported"]).not_to include("token")
    end

    it "advertises PKCE methods matching what the server enforces" do
      expect(json["code_challenge_methods_supported"])
        .to match_array(Doorkeeper.config.pkce_code_challenge_methods_supported)
      expect(json["code_challenge_methods_supported"]).to include("S256")
    end

    it "uses the configured issuer rather than the Host header" do
      expect(json["issuer"]).to eq(Doorkeeper::OpenidConnect.resolve_issuer)
    end
  end

  describe "GET /.well-known/openid-configuration" do
    before { get "/.well-known/openid-configuration" }

    it_behaves_like "a discovery document grounded in real configuration"

    it "returns JSON" do
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
    end

    it "advertises the signing algorithm the server actually signs with" do
      expect(json["id_token_signing_alg_values_supported"])
        .to eq([Doorkeeper::OpenidConnect.signing_algorithm.to_s])
      expect(json["id_token_signing_alg_values_supported"]).to eq(["RS256"])
    end

    it "advertises exactly the claims defined in the claims DSL, plus the registered ones" do
      configured = Doorkeeper::OpenidConnect.configuration.claims.to_h.keys.map(&:to_s)

      expect(json["claims_supported"]).to include(*configured)
      expect(json["claims_supported"]).to match_array(%w[iss sub aud exp iat] | configured)
    end

    it "points at a JWKS endpoint" do
      expect(json["jwks_uri"]).to end_with("/oauth/discovery/keys")
    end

    it "points at the userinfo endpoint" do
      expect(json["userinfo_endpoint"]).to end_with("/oauth/userinfo")
    end

    it "declares public subject types" do
      expect(json["subject_types_supported"]).to eq(["public"])
    end
  end

  # Weave advertised this path before the spec-canonical root one existed, so it
  # has to keep working — and has to serve the same document.
  describe "GET /oauth/.well-known/openid-configuration (legacy alias)" do
    before { get "/oauth/.well-known/openid-configuration" }

    it_behaves_like "a discovery document grounded in real configuration"

    it "serves the identical document as the canonical location" do
      legacy = response.parsed_body
      get "/.well-known/openid-configuration"

      expect(legacy).to eq(response.parsed_body)
    end
  end

  describe "GET /oauth/.well-known/oauth-authorization-server (RFC 8414)" do
    before { get "/oauth/.well-known/oauth-authorization-server" }

    it_behaves_like "a discovery document grounded in real configuration"

    it "returns the fields RFC 8414 requires" do
      expect(response).to have_http_status(:ok)
      expect(json).to include(
        "issuer", "authorization_endpoint", "token_endpoint",
        "response_types_supported", "grant_types_supported", "scopes_supported"
      )
    end

    it "includes the OAuth endpoints" do
      base = "http://www.example.com"

      expect(json["authorization_endpoint"]).to eq("#{base}/oauth/authorize")
      expect(json["token_endpoint"]).to eq("#{base}/oauth/token")
      expect(json["revocation_endpoint"]).to eq("#{base}/oauth/revoke")
      expect(json["introspection_endpoint"]).to eq("#{base}/oauth/introspect")
      expect(json["userinfo_endpoint"]).to eq("#{base}/oauth/userinfo")
      expect(json["jwks_uri"]).to eq("#{base}/oauth/discovery/keys")
    end

    it "advertises client authentication methods matching Doorkeeper's config" do
      expect(json["token_endpoint_auth_methods_supported"])
        .to match_array(%w[client_secret_basic client_secret_post])
    end
  end

  describe "GET /oauth/discovery/keys (JWKS)" do
    before { get "/oauth/discovery/keys" }

    it "serves exactly one signing key" do
      expect(response).to have_http_status(:ok)
      expect(json.fetch("keys").sole).to include("kid", "n", "e")
    end

    it "describes that key as an RS256 signing key" do
      key = json.fetch("keys").sole

      expect(key.slice("kty", "alg", "use")).to eq(
        "kty" => "RSA", "alg" => "RS256", "use" => "sig"
      )
    end

    it "never exposes private key material" do
      key = json.fetch("keys").sole

      # RFC 7517 §9.3 / RFC 7518 §6.3.2: these are the RSA private parameters.
      # If any of them are published, the signing key is compromised.
      expect(key.keys).not_to include("d", "p", "q", "dp", "dq", "qi", "oth")
    end

    it "serves a key that reconstructs into a public-only RSA key" do
      rsa = JWT::JWK.import(json.fetch("keys").sole.symbolize_keys).keypair

      expect(rsa).to be_a(OpenSSL::PKey::RSA)
      expect(rsa.private?).to be(false)
    end
  end
end
