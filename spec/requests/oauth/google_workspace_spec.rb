# frozen_string_literal: true

require "rails_helper"

# Google Workspace as an OIDC client of Weave, with AD passwords. Covers who
# has Google sign-in (the google-workspace group), the email claim (the
# address on the Workspace domains), the Google app's own rule (no code of
# conduct for anyone), and per-project onboarding (a sponsored project such as
# HackBoston needs no Patchwork Slack or code of conduct for other apps).
RSpec.describe "Google Workspace sign-in", type: :request do
  let(:setup) { GoogleWorkspaceApp.ensure!(redirect_uri: redirect_uri) }
  let(:directory) { use_fake_directory }

  def redirect_uri = "https://accounts.google.com/samlrp/oidc/acs/test"
  def google_app = setup.application
  def google_group = setup.group
  def code_verifier = @code_verifier ||= SecureRandom.urlsafe_base64(64)

  def authorization_params
    {
      client_id: google_app.uid, redirect_uri: redirect_uri, response_type: "code", scope: "openid email profile",
      code_challenge: Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(code_verifier), padding: false),
      code_challenge_method: "S256", nonce: "n-0S6_WzA2Mj"
    }
  end

  # Google sends the browser to /oauth/authorize. Weave asks for a sign-in,
  # and the person uses their AD password.
  def arrive_from_google_and_sign_in(user, password)
    get oauth_authorization_path, params: authorization_params
    post "/login", params: { user: { email: user.email, password: password } }
  end

  def approve_and_exchange
    post oauth_authorization_path, params: authorization_params
    expect(response).to have_http_status(:found)
    code = Rack::Utils.parse_query(URI.parse(response.location).query).fetch("code")

    post oauth_token_path, params: { grant_type: "authorization_code", code: code, redirect_uri: redirect_uri, code_verifier: code_verifier },
                           headers: { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(google_app.uid, google_app.plaintext_secret) }
    expect(response).to have_http_status(:ok)
    JWT.decode(response.parsed_body.fetch("id_token"), nil, false).first
  end

  describe "the app" do
    it "is restricted to the google-workspace group, with the OIDC scopes Google uses" do
      expect(google_app.access_policy).to eq("restricted")
      expect(google_app.requires_code_of_conduct).to be(false)
      expect(google_app.requires_guardian_consent).to be(true)
      expect(google_app.scopes.to_s).to eq("openid email profile")
      expect(ApplicationAccessGrant.for_application(google_app).map(&:grantee)).to eq([google_group])
      expect(google_app.email_domains).to include("patchworklabs.org", "hackboston.dev", "hackathon.help")
    end

    it "keeps its client id and secret when the setup runs again" do
      uid = google_app.uid

      again = GoogleWorkspaceApp.ensure!(redirect_uri: redirect_uri)

      expect(again.created).to be(false)
      expect(again.application.uid).to eq(uid)
      expect(ApplicationAccessGrant.for_application(google_app).count).to eq(1)
    end

    it "turns the code of conduct gate off again when the setup runs again" do
      google_app.update!(requires_code_of_conduct: true)

      GoogleWorkspaceApp.ensure!(redirect_uri: redirect_uri)

      expect(google_app.reload.requires_code_of_conduct).to be(false)
    end

    it "keeps email domains that an admin changed when the setup runs again" do
      google_app.update!(email_domains: %w[patchworklabs.org])

      GoogleWorkspaceApp.ensure!(redirect_uri: "https://accounts.google.com/new")

      expect(google_app.reload.email_domains).to eq(%w[patchworklabs.org])
      expect(google_app.redirect_uri).to eq("https://accounts.google.com/new")
    end
  end

  describe "a HackBoston member with no Slack and no code of conduct" do
    let(:hackboston) { create(:group, name: "HackBoston", waives_code_of_conduct: true, waives_slack: true) }
    let(:hackboston_user) { create(:user, :verified, email: "ada@hackboston.dev", first_name: "Ada", last_name: "Lovelace") }

    before do
      create(:group_membership, group: hackboston, user: hackboston_user)
      directory.add_user(hackboston_user.p_id, password: "Hack-password-1", ou: "OU=HackBoston,OU=Sponsored-Projects,OU=Users")
      DirectoryPasswords.link(hackboston_user)
    end

    it "signs in with the AD password and lands on the profile, not the Slack onboarding" do
      post "/login", params: { user: { email: hackboston_user.email, password: "Hack-password-1" } }
      follow_redirect!

      expect(response).to redirect_to(profile_path)
      expect(hackboston_user.reload.slack_member?).to be(false)
      expect(hackboston_user.slack_coc_accepted_at).to be_nil
    end

    it "uses the Google app when they have Google sign-in, and Google gets their hackboston.dev address" do
      create(:group_membership, group: google_group, user: hackboston_user)

      arrive_from_google_and_sign_in(hackboston_user, "Hack-password-1")
      expect(response.location).to include("/oauth/authorize")

      claims = approve_and_exchange
      expect(claims["email"]).to eq("ada@hackboston.dev")
      expect(claims["email_verified"]).to be(true)
      expect(claims["sub"]).to eq(hackboston_user.p_id)
    end

    it "gets the access-denied page, not an error, without Google sign-in" do
      arrive_from_google_and_sign_in(hackboston_user, "Hack-password-1")
      get oauth_authorization_path, params: authorization_params

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("You don't have access")
    end
  end

  describe "a Patchwork staff member" do
    let(:staff_user) { create(:user, :verified, email: "grace@patchworklabs.org", is_staff: true) }

    before do
      create(:group_membership, group: google_group, user: staff_user)
      directory.add_user(staff_user.p_id, password: "Staff-password-1")
      DirectoryPasswords.link(staff_user)
    end

    it "uses the Google app without having accepted the code of conduct" do
      expect(staff_user.slack_coc_accepted_at).to be_nil

      arrive_from_google_and_sign_in(staff_user, "Staff-password-1")

      expect(approve_and_exchange["email"]).to eq("grace@patchworklabs.org")
    end

    it "still needs the code of conduct for other apps" do
      other = Doorkeeper::Application.create!(name: "Other", redirect_uri: "https://other.example.com/cb", scopes: "openid profile")
      post "/login", params: { user: { email: staff_user.email, password: "Staff-password-1" } }

      get oauth_authorization_path, params: { client_id: other.uid, redirect_uri: other.redirect_uri, response_type: "code", scope: "openid profile" }

      expect(response).to redirect_to(slack_onboarding_path)
      expect(flash[:alert]).to include("Code of Conduct")
    end

    it "still lands on the Slack onboarding after sign-in" do
      post "/login", params: { user: { email: staff_user.email, password: "Staff-password-1" } }
      follow_redirect!

      expect(response).to redirect_to(slack_onboarding_path)
    end

  end

  describe "the email claim" do
    let(:member) { create(:user, :verified, :accepted_code_of_conduct, email: "personal@example.com") }

    before do
      create(:group_membership, group: google_group, user: member)
      directory.add_user(member.p_id, password: "Member-password-1")
      DirectoryPasswords.link(member)
    end

    it "is the confirmed Workspace address, not the personal primary address" do
      member.email_addresses.create!(email: "member@patchworklabs.org", confirmed_at: Time.current)

      arrive_from_google_and_sign_in(member, "Member-password-1")

      expect(approve_and_exchange["email"]).to eq("member@patchworklabs.org")
    end

    it "refuses a user with no confirmed address on the Workspace domains" do
      member.email_addresses.create!(email: "member@patchworklabs.org", confirmed_at: nil)

      arrive_from_google_and_sign_in(member, "Member-password-1")
      get oauth_authorization_path, params: authorization_params

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include("needs a confirmed address on")
    end

    it "stays the primary address for other apps" do
      other = Doorkeeper::Application.create!(name: "Other", redirect_uri: "https://other.example.com/cb", scopes: "openid email")
      token = Doorkeeper::AccessToken.create!(application: other, resource_owner_id: member.id, scopes: "openid email")

      get oauth_userinfo_path, headers: { "Authorization" => "Bearer #{token.plaintext_token || token.token}" }

      expect(response.parsed_body["email"]).to eq("personal@example.com")
    end
  end
end
