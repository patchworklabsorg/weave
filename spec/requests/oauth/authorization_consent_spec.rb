# frozen_string_literal: true

require "rails_helper"

# Coverage for the custom-styled Doorkeeper consent views
# (app/views/doorkeeper/authorizations/). The critical behavior is that the
# consent forms round-trip every pre-auth parameter — losing the OIDC nonce
# here would silently break clients that validate it in the id_token.
RSpec.describe "OAuth authorization consent screen", type: :request do
  let(:user) { create(:user, :verified, :accepted_code_of_conduct) }

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

  before { sign_in_via_magic_link(user) }

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

  # Regression coverage for a silent, browser-side breakage: the global CSP sets
  # `form-action 'self'`, and Chrome and Safari apply form-action to every hop of
  # a form submission's redirect chain. With only 'self' allowed, granting consent
  # POSTs fine and Doorkeeper answers 302 to the client, but the browser refuses
  # the cross-origin hop without a word — the Authorize button appears dead and
  # the server log shows a POST and a redirect that both look perfectly healthy.
  describe "form-action on the consent screen" do
    def form_action(response)
      directives = response.headers["Content-Security-Policy"].to_s.split(";").map(&:strip)
      directives.find { |directive| directive.start_with?("form-action ") }
    end

    it "allows the consent form to reach the client's registered redirect origin" do
      get oauth_authorization_path, params: authorization_params

      expect(response).to have_http_status(:ok)
      expect(form_action(response)).to eq("form-action 'self' https://client.example.com")
    end

    it "allows every origin the application registered, and each only once" do
      application.update!(
        redirect_uri: [
          "https://client.example.com/callback",
          "https://client.example.com/other",
          "https://second.example.com:8443/callback"
        ].join("\n")
      )

      get oauth_authorization_path, params: authorization_params(redirect_uri: "https://client.example.com/callback")

      expect(form_action(response)).to eq(
        "form-action 'self' https://client.example.com https://second.example.com:8443"
      )
    end

    it "keeps redirect URIs that are not http(s) out of the header" do
      application.update!(
        redirect_uri: ["urn:ietf:wg:oauth:2.0:oob", "https://client.example.com/callback"].join("\n")
      )

      get oauth_authorization_path, params: authorization_params

      expect(form_action(response)).to eq("form-action 'self' https://client.example.com")
      expect(form_action(response)).not_to include("urn:")
    end

    # The allowance comes from the application's registered URIs, not from the
    # parameter, so asking to be redirected elsewhere cannot widen the policy.
    it "does not allow an origin the request merely asked for" do
      get oauth_authorization_path, params: authorization_params(redirect_uri: "https://evil.example.com/callback")

      expect(form_action(response)).not_to include("evil.example.com")
    end

    it "leaves form-action alone everywhere else" do
      get root_path

      expect(form_action(response)).to eq("form-action 'self'")
    end
  end

  # Regression coverage for the second silent browser-side breakage on this
  # screen, and a close cousin of the form-action one above. Turbo submits forms
  # with fetch(), and both consent forms answer with a redirect to the client's
  # redirect_uri — cross-origin by definition. fetch() follows that hop as a CORS
  # request, so the client's callback is asked for OPTIONS rather than GET. A
  # preflight carries no cookies, so a callback that keeps its sign-in state in
  # one sees an empty jar and rejects a request the user made correctly. Both
  # forms have to submit as real navigations.
  describe "turbo on the consent screen" do
    it "opts both consent forms out of Turbo so they submit as navigations" do
      get oauth_authorization_path, params: authorization_params

      forms = Nokogiri::HTML(response.body).css("form[action='#{oauth_authorization_path}']")
      expect(forms.size).to eq(2)

      turbo = forms.to_h do |form|
        [form.at_css("input[name='_method']")&.[]("value") || "post", form["data-turbo"]]
      end

      expect(turbo).to eq("post" => "false", "delete" => "false")
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
