# frozen_string_literal: true

require "rails_helper"

# Signing in used to land everyone on the dashboard, wherever they had been
# going (#117).
RSpec.describe "Return to the requested page after sign-in", type: :request do
  let(:user) { create(:user, :verified) }

  def sign_in_with_magic_link
    link = User::MagicLink.issue!(user)
    get magic_link_login_path(token: link.token)
    post confirm_magic_link_path(token: link.token)
  end

  def take_return_path(value)
    controller = AuthController.new
    allow(controller).to receive(:session).and_return({ ReturnAfterSignIn::SESSION_KEY => value })
    controller.send(:take_return_path)
  end

  it "returns to the protected page after a magic-link sign-in" do
    get profile_sessions_path
    expect(response).to redirect_to("/login")

    get login_path
    post send_magic_link_path, params: { email: user.email }
    sign_in_with_magic_link

    expect(response).to redirect_to(profile_sessions_path)
  end

  it "keeps the query string" do
    get "#{profile_sessions_path}?tab=active"

    sign_in_with_magic_link

    expect(response).to redirect_to("#{profile_sessions_path}?tab=active")
  end

  it "returns to the protected page after a password sign-in" do
    directory = use_fake_directory
    directory.add_user(user.p_id, password: "Ad-password-1")
    DirectoryPasswords.link(user)

    get profile_sessions_path
    post "/login", params: { user: { email: user.email, password: "Ad-password-1" } }

    expect(response).to redirect_to(profile_sessions_path)
  end

  it "lands on the dashboard when no page asked for the sign-in" do
    sign_in_with_magic_link

    expect(response).to redirect_to(root_path)
  end

  it "uses the stored page once only" do
    get profile_sessions_path
    sign_in_with_magic_link
    delete logout_path

    sign_in_with_magic_link

    expect(response).to redirect_to(root_path)
  end

  it "prefers a pending OAuth authorization, and drops the stored page" do
    application = Doorkeeper::Application.create!(name: "Client", redirect_uri: "https://client.example.com/callback", scopes: "profile")
    get profile_sessions_path
    get oauth_authorization_path, params: { client_id: application.uid, redirect_uri: application.redirect_uri, response_type: "code", scope: "profile" }
    return_to = session[:oauth_return_to]

    sign_in_with_magic_link

    expect(response).to redirect_to(return_to)
    expect(session[ReturnAfterSignIn::SESSION_KEY]).to be_nil
  end

  it "does not store a JSON request" do
    get profile_sessions_path, headers: { "Accept" => "application/json" }

    expect(session[ReturnAfterSignIn::SESSION_KEY]).to be_nil
  end

  it "does not store a Turbo Frame request" do
    get profile_sessions_path, headers: { "Turbo-Frame" => "sessions" }

    expect(session[ReturnAfterSignIn::SESSION_KEY]).to be_nil
  end

  it "does not let a Turbo prefetch replace the stored page" do
    get profile_sessions_path
    get password_path, headers: { "X-Sec-Purpose" => "prefetch" }

    expect(session[ReturnAfterSignIn::SESSION_KEY]).to eq(profile_sessions_path)
  end

  it "does not store a form post" do
    post email_addresses_path

    expect(session[ReturnAfterSignIn::SESSION_KEY]).to be_nil
  end

  it "accepts a local path" do
    expect(take_return_path("/profile/sessions?tab=active")).to eq("/profile/sessions?tab=active")
  end

  # The session cookie is signed, so a request can't set these values today.
  # They are checked anyway, because the value goes straight into redirect_to.
  describe "unsafe stored values" do
    [
      "//evil.com",
      "//evil.com/path",
      "https://evil.com",
      "http://evil.com/profile",
      "javascript:alert(1)",
      "/\\evil.com",
      "\\\\evil.com",
      "/\\/evil.com",
      "/\t/evil.com",
      "/\n/evil.com",
      "evil.com",
      "profile/sessions",
      "/login",
      "/login?next=/profile",
      "/logout",
      "/oauth/login",
      "/auth/magic_link/abc123",
      "/#{"a" * ReturnAfterSignIn::MAX_LENGTH}"
    ].each do |value|
      it "rejects #{value.inspect.truncate(40)}" do
        expect(take_return_path(value)).to be_nil
      end
    end

    it "sends the person to the dashboard instead" do
      controller = AuthController.new
      controller.request = ActionDispatch::TestRequest.create
      allow(controller).to receive(:session).and_return({ ReturnAfterSignIn::SESSION_KEY => "//evil.com" })

      expect(controller.send(:post_login_destination)).to eq(root_path)
    end
  end
end
