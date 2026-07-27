# frozen_string_literal: true

require "rails_helper"

# End-to-end coverage of the OpenID Connect provider: a real authorization_code
# + PKCE flow, a real RS256 id_token verified against the real JWKS endpoint,
# and the userinfo endpoint. Nothing here is stubbed, because the bug this
# suite exists to prevent was precisely a gap between what we claimed to do and
# what we actually did.
RSpec.describe "OpenID Connect", type: :request do
  let(:user) { create(:user, :verified, phone_number: "+18025550123") }

  # Public (non-confidential) client, so `force_pkce` applies and the token
  # exchange is authenticated by the code_verifier rather than a secret.
  let(:application) do
    Doorkeeper::Application.create!(
      name: "Test Client",
      redirect_uri: redirect_uri,
      scopes: "openid profile email phone admin",
      confidential: false
    )
  end

  let(:code_verifier) { SecureRandom.urlsafe_base64(64) }

  def redirect_uri
    "https://client.example.com/callback"
  end

  def code_challenge
    Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(code_verifier), padding: false)
  end

  # Log in through the real magic-link flow so `resource_owner_authenticator`
  # finds session[:user_id] and a live user_sessions row exists for auth_time.
  def login(user)
    token = SecureRandom.urlsafe_base64(32)
    user.update!(
      magic_link_token: token,
      magic_link_expires_at: 15.minutes.from_now,
      magic_link_used_at: nil
    )
    get magic_link_login_path(token: token)
  end

  def authorize!(scope:, **extra)
    post oauth_authorization_path, params: {
      client_id: application.uid,
      redirect_uri: redirect_uri,
      response_type: "code",
      scope: scope,
      code_challenge: code_challenge,
      code_challenge_method: "S256",
      **extra
    }

    expect(response).to have_http_status(:found)
    Rack::Utils.parse_query(URI.parse(response.location).query).fetch("code")
  end

  def exchange!(code, **overrides)
    post oauth_token_path, params: {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: redirect_uri,
      client_id: application.uid,
      code_verifier: code_verifier
    }.merge(overrides)

    response.parsed_body
  end

  # Full happy path: returns the parsed token response.
  def obtain_tokens(scope:, **extra)
    login(user)
    exchange!(authorize!(scope: scope, **extra))
  end

  def jwks
    get oauth_discovery_keys_path
    JWT::JWK::Set.new(response.parsed_body.deep_symbolize_keys)
  end

  # Verifies signature, algorithm, issuer and audience against live config.
  def verify_id_token(id_token)
    JWT.decode(
      id_token, nil, true,
      algorithms: ["RS256"],
      jwks: jwks,
      iss: Doorkeeper::OpenidConnect.resolve_issuer,
      verify_iss: true,
      aud: application.uid,
      verify_aud: true
    )
  end

  describe "authorization_code + PKCE flow with scope=openid" do
    it "issues an id_token alongside the access token" do
      body = obtain_tokens(scope: "openid profile")

      expect(body).to include("access_token", "id_token", "refresh_token")
      expect(body["token_type"]).to eq("Bearer")
      expect(body["scope"]).to eq("openid profile")
    end

    # force_pkce is on, so a code cannot be redeemed by whoever intercepts it.
    it "rejects the exchange when the PKCE verifier is missing" do
      login(user)
      body = exchange!(authorize!(scope: "openid profile"), code_verifier: nil)

      expect(body).not_to include("id_token")
      expect(body["error"]).to eq("invalid_request")
      expect(body["error_description"]).to include("code_verifier")
    end

    it "rejects the exchange when the PKCE verifier is wrong" do
      login(user)
      body = exchange!(authorize!(scope: "openid profile"), code_verifier: SecureRandom.urlsafe_base64(64))

      expect(body).not_to include("id_token")
      expect(body["error"]).to eq("invalid_grant")
    end

    it "omits the id_token when the openid scope was not granted" do
      body = obtain_tokens(scope: "profile email")

      expect(body).to include("access_token")
      expect(body).not_to include("id_token")
    end
  end

  describe "the id_token" do
    subject(:decoded) { verify_id_token(obtain_tokens(scope: "openid profile email")["id_token"]) }

    # Plain methods rather than `let`s: `decoded` is already memoized, so these
    # are just projections of it.
    def claims = decoded.first
    def header = decoded.last

    it "is RS256-signed and verifies against the published JWKS" do
      expect(header["alg"]).to eq("RS256")
      expect(header["typ"]).to eq("JWT")
    end

    it "is signed with a key that the JWKS endpoint actually publishes" do
      expect(jwks.map(&:kid)).to include(header["kid"])
    end

    it "has a sub equal to the user's p_id, not the primary key" do
      expect(claims["sub"]).to eq(user.p_id)
      expect(claims["sub"]).to match(/\APWL\d[a-fA-F0-9]{9}\z/)
      expect(claims["sub"]).not_to eq(user.id.to_s)
    end

    it "carries the registered claims" do
      expect(claims["iss"]).to eq(Doorkeeper::OpenidConnect.resolve_issuer)
      expect(claims["aud"]).to eq(application.uid)
      expect(claims["exp"]).to be > claims["iat"]
    end

    it "reports auth_time from the user's live session" do
      expect(claims["auth_time"]).to eq(user.user_sessions.maximum(:created_at).to_i)
    end

    it "carries the granted scopes' claims and nothing else" do
      expect(claims).to include(
        "name"               => user.full_name,
        "given_name"         => user.first_name,
        "family_name"        => user.last_name,
        "preferred_username" => user.username,
        "email"              => user.email,
        "email_verified"     => true
      )
      expect(claims).not_to include("phone_number", "phone_number_verified", "admin")
    end

    it "rejects a token whose signature does not match the JWKS" do
      id_token = obtain_tokens(scope: "openid profile")["id_token"]
      tampered = "#{id_token[0..-6]}AAAAA"

      expect { verify_id_token(tampered) }.to raise_error(JWT::DecodeError)
    end
  end

  describe "GET /oauth/userinfo" do
    def userinfo(scope:)
      token = obtain_tokens(scope: scope).fetch("access_token")
      get oauth_userinfo_path, headers: { "Authorization" => "Bearer #{token}" }
      response.parsed_body
    end

    it "returns the same sub as the id_token" do
      body = obtain_tokens(scope: "openid profile")
      claims = verify_id_token(body["id_token"]).first

      get oauth_userinfo_path, headers: { "Authorization" => "Bearer #{body['access_token']}" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["sub"]).to eq(claims["sub"]).and eq(user.p_id)
    end

    it "returns profile claims for the profile scope" do
      expect(userinfo(scope: "openid profile")).to include(
        "name"               => user.full_name,
        "given_name"         => user.first_name,
        "family_name"        => user.last_name,
        "preferred_username" => user.username,
        "updated_at"         => user.updated_at.to_i
      )
    end

    it "returns email claims for the email scope" do
      expect(userinfo(scope: "openid email")).to include(
        "email"          => user.email,
        "email_verified" => true
      )
    end

    it "returns phone claims for the phone scope, unverified" do
      expect(userinfo(scope: "openid phone")).to include(
        "phone_number"          => "+18025550123",
        "phone_number_verified" => false
      )
    end

    it "returns the admin claim for the admin scope" do
      user.update!(role: :admin)

      expect(userinfo(scope: "openid admin")).to include("admin" => true)
    end

    it "does not leak claims from scopes that were not granted" do
      body = userinfo(scope: "openid profile")

      expect(body.keys).to match_array(
        %w[sub name given_name family_name preferred_username updated_at]
      )
    end

    it "does not leak email or phone into a profile-only response" do
      body = userinfo(scope: "openid profile")

      expect(body).not_to include("email", "email_verified", "phone_number", "admin")
    end

    # Weave served userinfo to any valid access token long before OIDC existed
    # here. The gem's own controller would 403 these; ours must not.
    it "still serves tokens that never asked for the openid scope" do
      body = userinfo(scope: "profile email")

      expect(response).to have_http_status(:ok)
      expect(body).to include("sub" => user.p_id, "email" => user.email)
    end

    it "rejects an unauthenticated request" do
      get oauth_userinfo_path

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
