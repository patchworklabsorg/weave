# frozen_string_literal: true

# Sign-in helpers for the app's custom (session[:user_id]) authentication.
module ControllerAuthHelpers
  # For controller specs: stub the authentication chain so the given user is the
  # current user without touching the session/session-tracking machinery.
  def sign_in(user)
    allow(controller).to receive_messages(current_user: user, authenticate_user!: true, track_user_session: true, current_user_session: nil)
  end
end

# For request specs: drive the real magic-link flow. Signing in is a POST — the
# GET only renders the confirmation screen — so this issues a link and submits
# it the way the button does.
module RequestAuthHelpers
  def sign_in_via_magic_link(user)
    link = User::MagicLink.issue!(user)
    post confirm_magic_link_path(token: link.token)
    link
  end
end

module FeatureAuthHelpers
  # For feature specs: log in through the real magic-link flow, including the
  # confirmation click. The user must be email-verified to clear
  # authenticate_user!.
  def sign_in(user)
    user.update!(email_confirmed_at: Time.current) unless user.email_verified?
    link = User::MagicLink.issue!(user)
    visit magic_link_login_path(token: link.token)
    click_button "Sign in"
  end
end

RSpec.configure do |config|
  config.include ControllerAuthHelpers, type: :controller
  config.include RequestAuthHelpers, type: :request
  config.include FeatureAuthHelpers, type: :feature
end
