# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Session revocation", type: :request do
  # Log in through the real magic-link flow so complete_login establishes a
  # validatable user_sessions record for the cookie.
  def login(user)
    token = SecureRandom.urlsafe_base64(32)
    user.update!(
      magic_link_token: token,
      magic_link_expires_at: 15.minutes.from_now,
      magic_link_used_at: nil
    )
    get magic_link_login_path(token: token)
  end

  let(:user) { create(:user, :verified) }

  it "authenticates a freshly logged-in session" do
    login(user)

    get profile_path

    expect(response).to have_http_status(:ok)
  end

  it "stops authenticating once the user is locked" do
    login(user)

    user.lock!

    get profile_path
    expect(response).to redirect_to("/login")
  end

  it "stops authenticating once the session is signed out (sign out of all)" do
    login(user)

    user.user_sessions.update_all(signed_out_at: Time.current)

    get profile_path
    expect(response).to redirect_to("/login")
  end

  it "stops authenticating once the session has expired" do
    login(user)

    user.user_sessions.update_all(expiration_at: 1.hour.ago)

    get profile_path
    expect(response).to redirect_to("/login")
  end

  it "stops authenticating once the account is no longer active" do
    login(user)

    user.deactivate!

    get profile_path
    expect(response).to redirect_to("/login")
  end
end
