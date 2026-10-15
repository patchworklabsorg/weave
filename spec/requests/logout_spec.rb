# frozen_string_literal: true

require "rails_helper"

# Logout used to delete session[:user_id] and nothing else. The user_sessions
# row stayed live, so a copy of the cookie taken before logout still signed in.
RSpec.describe "Logging out", type: :request do
  let(:user) { create(:user, :verified) }

  it "signs out the user_sessions row behind the cookie" do
    sign_in_via_magic_link(user)
    user_session = user.user_sessions.sole

    delete logout_path

    expect(response).to redirect_to(login_path)
    expect(session[:user_id]).to be_nil
    expect(user_session.reload.signed_out_at).to be_present
    expect(user_session).to be_expired
  end

  it "does not let a cookie copied before logout sign in again" do
    sign_in_via_magic_link(user)
    stolen_cookie = cookies["_weave_session"]

    delete logout_path

    cookies["_weave_session"] = stolen_cookie
    get profile_path

    expect(response).to redirect_to("/login")
  end

  it "leaves the user's other sessions signed in" do
    other = user.user_sessions.create!(session_token: "other-device", expiration_at: 30.days.from_now)
    sign_in_via_magic_link(user)

    delete logout_path

    expect(other.reload.signed_out_at).to be_nil
  end
end
