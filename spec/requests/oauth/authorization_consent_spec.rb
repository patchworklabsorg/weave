# frozen_string_literal: true

require "rails_helper"

# Coverage for the custom-styled Doorkeeper consent views
# (app/views/doorkeeper/authorizations/). The critical behavior is that the
# consent forms round-trip every pre-auth parameter — losing the OIDC nonce
# here would silently break clients that validate it in the id_token.
RSpec.describe "OAuth authorization consent screen", type: :request do
  let(:user) { create(:user, :verified) }

  let(:application) do
    Doorkeeper::Application.create!(
      name: "Test Client",
      redirect_uri: "https://client.example.com/callback",
      scopes: "openid profile email phone admin",
      confidential: false
    )
  end

  let(:code_verifier) { SecureRandom.urlsafe_base64(64) }

  def code_challenge
    Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(code_verifier), padding: false)
  end

  def login(user)
    token = SecureRandom.urlsafe_base64(32)
    user.update!(
      magic_link_token: token,
      magic_link_expires_at: 15.minutes.from_now,
      magic_link_used_at: nil
    )
    get magic_link_login_path(token: token)
  end

  def authorization_params(**overrides)
    {
      client_id: application.uid,
      redirect_uri: application.redirect_uri,
      response_type: "code",
      scope: "openid email",
      code_challenge: code_challenge,
      code_challenge_method: "S256",
      nonce: "consent-nonce-123"
    }.merge(overrides)
  end

  before { login(user) }

  describe "GET /oauth/authorize" do
    it "renders the styled consent screen with the client name and scope descriptions" do
      get oauth_authorization_path, params: authorization_params

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Authorization required")
      expect(response.body).to include(application.name)
      expect(response.body).to include("Authenticate your account")
      expect(response.body).to include("View your email address")
      expect(response.body).to include("client.example.com")
    end

    it "renders both an authorize and a deny form that round-trip the pre-auth params" do
      get oauth_authorization_path, params: authorization_params

      body = Nokogiri::HTML(response.body)
      forms = body.css("form[action='#{oauth_authorization_path}']")
      expect(forms.size).to eq(2)

      forms.each do |form|
        %w[client_id redirect_uri response_type scope code_challenge code_challenge_method].each do |field|
          expect(form.at_css("input[name='#{field}']")).to be_present, "expected hidden field #{field}"
        end
        expect(form.at_css("input[name='nonce']")&.[]("value")).to eq("consent-nonce-123")
      end
    end

    it "translates the admin scope" do
      get oauth_authorization_path, params: authorization_params(scope: "openid admin")

      expect(response.body).to include("Perform administrative actions on your behalf")
      expect(response.body).not_to include("translation missing")
    end

    it "renders the styled error screen for an invalid request" do
      get oauth_authorization_path, params: authorization_params(scope: "bogus")

      expect(response).to have_http_status(:bad_request)
      expect(response.body).to include("scope is invalid")
    end
  end

  describe "POST /oauth/authorize with the consent form's fields" do
    it "issues a code whose id_token carries the nonce from the form" do
      post oauth_authorization_path, params: authorization_params
      expect(response).to have_http_status(:found)

      code = Rack::Utils.parse_query(URI.parse(response.location).query).fetch("code")
      post oauth_token_path, params: {
        grant_type: "authorization_code",
        code: code,
        redirect_uri: application.redirect_uri,
        client_id: application.uid,
        code_verifier: code_verifier
      }

      id_token = response.parsed_body.fetch("id_token")
      payload, = JWT.decode(id_token, nil, false)
      expect(payload["nonce"]).to eq("consent-nonce-123")
    end
  end
end
