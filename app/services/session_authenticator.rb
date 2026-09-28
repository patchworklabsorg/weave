# frozen_string_literal: true

# Resolves which user, if any, a browser session is signed in as.
#
# A cookie carrying session[:user_id] is not sufficient on its own: the
# matching user_sessions record must still exist, be neither signed out nor
# expired, and the authenticating account must be unlocked and active. This
# is what makes User#lock!, suspension, single-session revocation and "sign out
# of all sessions" actually terminate access (and stops a stolen cookie from
# being valid forever).
#
# This is the one place that decision is made. ApplicationController uses it,
# and so do the places that don't inherit from ApplicationController: Doorkeeper's
# resource_owner_authenticator and admin_authenticator
# (config/initializers/doorkeeper.rb) and AdminConstraint (lib/admin_constraint.rb).
# When those had their own, weaker checks, a locked or suspended user could still
# complete an OAuth sign-in to every client, and a signed-out admin cookie still
# opened the engines mounted under /admin.
class SessionAuthenticator
  def initialize(session)
    @session = session
  end

  # The signed-in user, or nil when the session isn't signed in or is no longer
  # valid. Callers that own the session should reset it on nil when
  # session[:user_id] was present (see ApplicationController#load_authenticated_user).
  def user
    return nil if @session[:user_id].blank?

    user = User.find_by(id: @session[:user_id])
    return nil if user.nil?

    # During impersonation the real, authenticating identity is the admin
    # (session[:admin_id]); their session record is the one that was created at
    # login and is what we must validate.
    authenticating_user =
      if @session[:admin_id].present?
        User.find_by(id: @session[:admin_id]) || user
      else
        user
      end

    return nil unless authenticating_user.can_authenticate?
    return nil unless valid_session_record?(authenticating_user)

    user
  end

  private

  # A live user_sessions row must back the cookie: present, not signed out and
  # not past its expiration.
  def valid_session_record?(user)
    return false if @session.id.blank?

    record = user.user_sessions.find_by(session_token: @session.id.to_s)
    return false if record.nil?

    record.signed_out_at.nil? && !record.expired?
  end

end
