# frozen_string_literal: true

require "rails_helper"

# Following a magic link used to sign you in on the GET. Everything that scans
# an inbox — Outlook Safe Links, Proofpoint, Slack unfurls, browser prefetch —
# issues that GET, so the link was routinely spent before its owner clicked it
# and they were told it had expired minutes after it was sent.
RSpec.describe "Magic link sign-in", type: :request do
  let(:user) { create(:user, :verified) }

  describe "GET /auth/magic_link/:token" do
    it "asks for confirmation instead of signing anyone in" do
      link = User::MagicLink.issue!(user)

      get magic_link_login_path(token: link.token)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Confirm your sign in")
      expect(response.body).to include(user.email)
      expect(session[:user_id]).to be_nil
    end

    it "leaves the link usable, however many times it is fetched" do
      link = User::MagicLink.issue!(user)

      3.times { get magic_link_login_path(token: link.token) }

      expect(link.reload).to be_live

      post confirm_magic_link_path(token: link.token)

      expect(session[:user_id]).to eq(user.id)
    end
  end

  describe "POST /auth/magic_link/:token" do
    it "signs the user in and spends the link" do
      link = User::MagicLink.issue!(user)

      post confirm_magic_link_path(token: link.token)

      expect(session[:user_id]).to eq(user.id)
      expect(link.reload).to be_used
    end

    it "refuses the same link twice" do
      link = User::MagicLink.issue!(user)
      post confirm_magic_link_path(token: link.token)
      delete logout_path

      post confirm_magic_link_path(token: link.token)

      expect(session[:user_id]).to be_nil
      expect(flash[:alert]).to eq(AuthController::MAGIC_LINK_ERRORS[:used])
    end
  end

  # One message for every failure sent people hunting an expiry problem they
  # did not have. These are three different things to do about it.
  describe "rejection messages" do
    it "says so when the link has expired" do
      link = create(:user_magic_link, :expired, user: user)

      get magic_link_login_path(token: link.token)

      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to eq(AuthController::MAGIC_LINK_ERRORS[:expired])
    end

    it "says so when the link was already used" do
      link = create(:user_magic_link, :used, user: user)

      get magic_link_login_path(token: link.token)

      expect(flash[:alert]).to eq(AuthController::MAGIC_LINK_ERRORS[:used])
    end

    it "says so when the token is unrecognized" do
      get magic_link_login_path(token: "not-a-real-token")

      expect(flash[:alert]).to eq(AuthController::MAGIC_LINK_ERRORS[:unknown])
    end
  end

  # A second link no longer invalidates the first, which is what made a
  # two-minute-old link fail for anyone who submitted the form twice.
  it "honours an earlier link after a newer one is issued" do
    first = User::MagicLink.issue!(user)
    User::MagicLink.issue!(user)

    post confirm_magic_link_path(token: first.token)

    expect(session[:user_id]).to eq(user.id)
  end

  it "re-opening a link you already used lands you in the app, not on an error" do
    link = User::MagicLink.issue!(user)
    post confirm_magic_link_path(token: link.token)

    get magic_link_login_path(token: link.token)

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to be_nil
  end

  # Sessions created at login used to carry only the raw user agent, so the
  # sessions pages showed them as "Legacy Session" with no OS or fingerprint.
  describe "session device metadata" do
    it "records parsed browser, OS, fingerprint, and timezone on the new session" do
      link = User::MagicLink.issue!(user)

      post confirm_magic_link_path(token: link.token),
           params: { fingerprint: "fp-visitor-id", timezone: "America/New_York" },
           headers: { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36" }

      session_record = user.user_sessions.order(:created_at).last
      expect(session_record.device_info).to eq("Chrome 150")
      expect(session_record.os_info).to eq("macOS 10.15.7")
      expect(session_record.fingerprint).to eq("fp-visitor-id")
      expect(session_record.timezone).to eq("America/New_York")
    end

    it "still signs in when the fingerprint fields were not submitted" do
      link = User::MagicLink.issue!(user)

      post confirm_magic_link_path(token: link.token)

      expect(session[:user_id]).to eq(user.id)
      session_record = user.user_sessions.order(:created_at).last
      expect(session_record.fingerprint).to be_nil
      expect(session_record.timezone).to be_nil
    end
  end

  it "confirms an unconfirmed address on sign-in" do
    unconfirmed = create(:user, :unverified)
    link = User::MagicLink.issue!(unconfirmed)

    post confirm_magic_link_path(token: link.token)

    expect(unconfirmed.reload).to be_email_verified
  end
end
