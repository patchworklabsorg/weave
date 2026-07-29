# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Session revocation", type: :request do
  # Signing in goes through the real magic-link flow so complete_login
  # establishes a validatable user_sessions record for the cookie.
  let(:user) { create(:user, :verified) }

  it "authenticates a freshly logged-in session" do
    sign_in_via_magic_link(user)

    get profile_path

    expect(response).to have_http_status(:ok)
  end

  it "stops authenticating once the user is locked" do
    sign_in_via_magic_link(user)

    user.lock!

    get profile_path
    expect(response).to redirect_to("/login")
  end

  it "stops authenticating once the session is signed out (sign out of all)" do
    sign_in_via_magic_link(user)

    user.user_sessions.update_all(signed_out_at: Time.current)

    get profile_path
    expect(response).to redirect_to("/login")
  end

  it "stops authenticating once the session has expired" do
    sign_in_via_magic_link(user)

    user.user_sessions.update_all(expiration_at: 1.hour.ago)

    get profile_path
    expect(response).to redirect_to("/login")
  end

  it "stops authenticating once the account is no longer active" do
    sign_in_via_magic_link(user)

    user.deactivate!

    get profile_path
    expect(response).to redirect_to("/login")
  end
end
