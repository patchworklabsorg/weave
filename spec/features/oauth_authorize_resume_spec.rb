# frozen_string_literal: true

require "rails_helper"

# An authorize request that finds nobody signed in sends the visitor to sign in
# or sign up. Signing in with a magic link means leaving for an email client, so
# the request must survive that trip and resume afterwards, or the client app
# waits for a callback that never comes (see hackclub/auth#49).
#
# The app opts out of the code of conduct so these flows stop at the consent
# screen. The code of conduct return is covered in slack_onboarding_spec.rb.
RSpec.feature "OAuth authorize resumes after sign-in", type: :feature do
  include ActiveJob::TestHelper

  let(:application) do
    Doorkeeper::Application.create!(
      name: "Test Client",
      redirect_uri: "https://client.example.com/callback",
      scopes: "openid profile email",
      confidential: false,
      requires_code_of_conduct: false
    )
  end

  let(:code_verifier) { SecureRandom.urlsafe_base64(64) }

  let(:authorize_params) do
    {
      client_id: application.uid,
      redirect_uri: application.redirect_uri,
      response_type: "code",
      scope: "openid email",
      state: "client-state-123",
      code_challenge: Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest(code_verifier), padding: false),
      code_challenge_method: "S256"
    }
  end

  # The client's callback is on another host, so the last redirect leaves the
  # app. Rack::Test still follows it, and current_url shows where it went.
  def expect_code_delivered_to_client
    callback = URI.parse(page.current_url)
    query = Rack::Utils.parse_query(callback.query)

    expect("#{callback.scheme}://#{callback.host}#{callback.path}").to eq(application.redirect_uri)
    expect(query["state"]).to eq("client-state-123")

    grant = Doorkeeper::AccessGrant.by_token(query["code"])
    expect(grant).to be_present
    expect(grant.application).to eq(application)
    expect(grant.code_challenge).to eq(authorize_params[:code_challenge])
    grant
  end

  # The token in the most recent sign-in email, read from the link in its body.
  def magic_link_path_from_last_email
    perform_enqueued_jobs
    mail = ActionMailer::Base.deliveries.last
    expect(mail).to be_present
    body = mail.html_part&.body&.decoded || mail.body.decoded
    URI.parse(body[/https?:\/\/[^\s"<>]+\/auth\/magic_link\/[^\s"<>]+/]).path
  end

  def sign_up(email:)
    click_link "Sign up"
    fill_in "First name", with: "Ada"
    fill_in "Last name", with: "Lovelace"
    fill_in "Email", with: email
    fill_in "Birthday", with: "2000-01-01"
    click_button "Create account"
  end

  def request_magic_link(email)
    fill_in "Email address", with: email
    click_button "Send magic link"
  end

  def open_magic_link(path)
    visit path
    click_button "Sign in"
  end

  def approve
    expect(page).to have_text("Authorization required")
    expect(page).to have_text(application.name)
    click_button "Authorize"
  end

  before { ActionMailer::Base.deliveries.clear }

  scenario "a new member signs up, confirms with the emailed link, and the flow resumes" do
    visit oauth_authorization_path(authorize_params)
    expect(page).to have_current_path(/\A\/oauth\/login/)

    sign_up(email: "ada@example.com")
    open_magic_link(magic_link_path_from_last_email)

    expect(User.find_by(email: "ada@example.com")).to be_email_verified
    approve
    expect_code_delivered_to_client
  end

  scenario "an existing member signs in with a magic link and the flow resumes" do
    user = create(:user, :verified, email: "grace@example.com")

    visit oauth_authorization_path(authorize_params)
    request_magic_link(user.email)
    open_magic_link(magic_link_path_from_last_email)

    approve
    expect(expect_code_delivered_to_client.resource_owner_id).to eq(user.id)
  end

  scenario "a new member opens the emailed link in a different browser and the flow resumes there" do
    visit oauth_authorization_path(authorize_params)
    sign_up(email: "ada@example.com")
    path = magic_link_path_from_last_email

    using_session(:other_browser) do
      open_magic_link(path)

      approve
      expect_code_delivered_to_client
    end
  end

  scenario "an existing member opens the magic link in a different browser and the flow resumes there" do
    user = create(:user, :verified, email: "grace@example.com")

    visit oauth_authorization_path(authorize_params)
    request_magic_link(user.email)
    path = magic_link_path_from_last_email

    using_session(:other_browser) do
      open_magic_link(path)

      approve
      expect(expect_code_delivered_to_client.resource_owner_id).to eq(user.id)
    end
  end

  scenario "a magic link requested without a pending authorize request signs in to the dashboard" do
    user = create(:user, :verified, email: "grace@example.com")

    visit login_path
    request_magic_link(user.email)
    open_magic_link(magic_link_path_from_last_email)

    expect(page).to have_text("Signed in.")
    expect(page).to have_no_current_path(/\A\/oauth\/authorize/)
  end
end
