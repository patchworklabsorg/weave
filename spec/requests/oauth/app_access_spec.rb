# frozen_string_literal: true

require "rails_helper"

# A restricted app is usable only by users with an access grant (see
# AppAccess). Checking at the consent screen alone would leave refresh
# tokens, userinfo and introspection working after access is removed, so
# every endpoint that hands out or honors a user's token checks too.
RSpec.describe "OAuth access to restricted apps", type: :request do
  let(:user) { create(:user, :verified) }
  let(:group) { create(:group) }
  let(:redirect_uri) { "https://client.example.com/callback" }
  let(:code_verifier) { SecureRandom.urlsafe_base64(64) }

  let(:application) do
    Doorkeeper::Application.create!(
      name: "Restricted Client",
      redirect_uri: redirect_uri,
      scopes: "openid profile email",
      confidential: true
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

  def authorization_code
    post oauth_authorization_path, params: authorization_params
    expect(response).to have_http_status(:found)
    Rack::Utils.parse_query(URI.parse(response.location).query).fetch("code")
  end

  def client_auth
    { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(application.uid, application.plaintext_secret) }
  end

  def exchange(code)
    post oauth_token_path, params: {
      grant_type: "authorization_code", code: code, redirect_uri: redirect_uri, code_verifier: code_verifier
    }, headers: client_auth
    response.parsed_body
  end

  def refresh(refresh_token)
    post oauth_token_path, params: { grant_type: "refresh_token", refresh_token: refresh_token }, headers: client_auth
    response.parsed_body
  end

  def userinfo_status(access_token)
    get oauth_userinfo_path, headers: { "Authorization" => "Bearer #{access_token}" }
    response.status
  end

  def introspect(access_token)
    post oauth_introspect_path, params: { token: access_token }, headers: client_auth
    response.parsed_body
  end

  def give_access
    create(:group_membership, group: group, user: user)
    ApplicationAccessGrant.create!(application: application, grantee: group)
  end

  def obtain_tokens
    sign_in_via_magic_link(user)
    exchange(authorization_code)
  end

  def restrict! = application.update!(access_policy: "restricted")

  # Removes access without any callback that might revoke tokens, so these
  # tests show the endpoint's own check.
  def remove_access = Group::Membership.where(user: user).delete_all

  it "leaves an app that is open to everyone unchanged" do
    sign_in_via_magic_link(user)

    get oauth_authorization_path, params: authorization_params

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Authorization required")
  end

  describe "the code-of-conduct requirement" do
    before { Flipper.enable(AppAccess::CODE_OF_CONDUCT_FLAG) }
    after { Flipper.remove(AppAccess::CODE_OF_CONDUCT_FLAG) }

    it "sends a user who has not accepted to accept, then back to the app" do
      user.update!(slack_id: "U1", slack_membership: "member")
      sign_in_via_magic_link(user)

      get oauth_authorization_path, params: authorization_params

      expect(response).to redirect_to(slack_onboarding_path)
      authorize_path = URI.parse(request.url).request_uri

      post accept_code_of_conduct_slack_onboarding_path

      expect(response).to redirect_to(authorize_path)
      follow_redirect!
      expect(response.body).to include("Authorization required")
    end

    it "refuses the consent POST" do
      sign_in_via_magic_link(user)

      post oauth_authorization_path, params: authorization_params

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("Accept the Code of Conduct")
    end

    it "stops a refresh token once acceptance is required" do
      user.update!(slack_coc_accepted_at: 1.day.ago)
      tokens = obtain_tokens
      user.update_columns(slack_coc_accepted_at: nil) # rubocop:disable Rails/SkipsModelValidations

      expect(refresh(tokens["refresh_token"])["error"]).to be_present
      expect(userinfo_status(tokens["access_token"])).to eq(401)
    end
  end

  describe "the authorization endpoint" do
    before { restrict! }

    it "shows a Weave page, not a redirect, to a user without access" do
      sign_in_via_magic_link(user)

      get oauth_authorization_path, params: authorization_params

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("You don't have access", "Restricted Client")
    end

    it "refuses the consent POST too, so a crafted form can't skip the screen" do
      sign_in_via_magic_link(user)

      post oauth_authorization_path, params: authorization_params

      expect(response).to have_http_status(:forbidden)
      expect(Doorkeeper::AccessGrant.count).to eq(0)
    end

    it "records the refusal" do
      sign_in_via_magic_link(user)

      # Ahoy skips requests without a browser user agent as bots.
      expect { get oauth_authorization_path, params: authorization_params, headers: { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36" } }
        .to change { Ahoy::Event.where(name: "OAuth access denied").count }.by(1)
    end

    it "shows the consent screen to a user with access through a group" do
      give_access
      sign_in_via_magic_link(user)

      get oauth_authorization_path, params: authorization_params

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Authorization required")
    end

    it "still sends a signed-out user to sign in first" do
      get oauth_authorization_path, params: authorization_params

      expect(response).to redirect_to("/oauth/login?client_id=#{application.uid}")
    end
  end

  describe "tokens issued before access was removed" do
    before do
      restrict!
      give_access
    end

    it "stops an unredeemed code from being exchanged" do
      sign_in_via_magic_link(user)
      code = authorization_code

      remove_access
      body = exchange(code)

      expect(body["error"]).to eq("invalid_grant")
      expect(body).not_to include("access_token")
    end

    it "stops the refresh token, and leaves no usable token behind" do
      tokens = obtain_tokens
      expect(refresh(tokens["refresh_token"])).to include("access_token")

      remove_access
      existing_ids = Doorkeeper::AccessToken.pluck(:id)
      body = refresh(Doorkeeper::AccessToken.last.plaintext_refresh_token || tokens["refresh_token"])

      expect(body["error"]).to eq("invalid_grant")
      expect(Doorkeeper::AccessToken.where.not(id: existing_ids).where(revoked_at: nil)).to be_empty
    end

    it "stops the access token at userinfo" do
      tokens = obtain_tokens
      expect(userinfo_status(tokens["access_token"])).to eq(200)

      remove_access

      expect(userinfo_status(tokens["access_token"])).to eq(401)
      expect(response.headers["WWW-Authenticate"]).to include('error="invalid_token"')
    end

    it "reports the access token as inactive at introspection, with no reason" do
      tokens = obtain_tokens
      expect(introspect(tokens["access_token"])["active"]).to be(true)

      remove_access

      expect(introspect(tokens["access_token"])).to eq("active" => false)
    end

    it "stops tokens when an open app is restricted" do
      application.update!(access_policy: "everyone")
      Group::Membership.delete_all
      tokens = obtain_tokens

      restrict!

      expect(userinfo_status(tokens["access_token"])).to eq(401)
      expect(refresh(tokens["refresh_token"])["error"]).to eq("invalid_grant")
    end
  end

  it "does not affect client_credentials tokens, which have no user" do
    restrict!

    post oauth_token_path, params: { grant_type: "client_credentials" }, headers: client_auth

    expect(response.parsed_body).to include("access_token")
  end
end
