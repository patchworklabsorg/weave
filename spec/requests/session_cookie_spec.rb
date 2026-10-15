# frozen_string_literal: true

require "rails_helper"

# A session cookie without Expires is dropped when the browser closes, which
# sent people back to the magic-link form on almost every visit (#199).
RSpec.describe "Session cookie", type: :request do
  let(:user) { create(:user, :verified) }

  def session_cookie_header
    Array(response.headers["Set-Cookie"]).flat_map { |h| h.split("\n") }
                                         .find { |c| c.start_with?("_weave_session=") }
  end

  def cookie_expiry
    Time.httpdate(session_cookie_header[/expires=([^;]+)/i, 1])
  end

  it "persists the sign-in cookie past the browser session" do
    sign_in_via_magic_link(user)

    expect(session_cookie_header).to be_present
    expect(cookie_expiry).to be_within(1.minute).of(Time.current + 30.days.to_i)
  end

  it "renews the cookie expiry on later requests" do
    sign_in_via_magic_link(user)

    travel 10.days do
      get profile_path

      expect(response).to have_http_status(:ok)
      expect(cookie_expiry).to be_within(1.minute).of(Time.current + 30.days.to_i)
    end
  end

  it "still signs the user out when the session row expires" do
    sign_in_via_magic_link(user)

    travel(user.session_duration_seconds.seconds + 1.minute) do
      get profile_path

      expect(response).to redirect_to("/login")
    end
  end
end
