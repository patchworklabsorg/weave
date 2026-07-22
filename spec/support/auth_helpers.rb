# frozen_string_literal: true

# Sign-in helpers for the app's custom (session[:user_id]) authentication.
module ControllerAuthHelpers
  # For controller specs: stub the authentication chain so the given user is the
  # current user without touching the session/session-tracking machinery.
  def sign_in(user)
    allow(controller).to receive(:current_user).and_return(user)
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:track_user_session).and_return(true)
    allow(controller).to receive(:current_user_session).and_return(nil)
  end
end

module FeatureAuthHelpers
  # For feature specs: log in through the real magic-link flow. The user must be
  # email-verified to clear authenticate_user!.
  def sign_in(user)
    user.update!(email_confirmed_at: Time.current) unless user.email_verified?
    token = SecureRandom.urlsafe_base64(32)
    user.update!(
      magic_link_token: token,
      magic_link_expires_at: 15.minutes.from_now,
      magic_link_used_at: nil
    )
    visit magic_link_login_path(token: token)
  end
end

RSpec.configure do |config|
  config.include ControllerAuthHelpers, type: :controller
  config.include FeatureAuthHelpers, type: :feature
end
