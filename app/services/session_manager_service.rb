# frozen_string_literal: true

class SessionManagerService
  def initialize(session_hash)
    @session = session_hash
  end

  # Sign in a user
  def sign_in(user, remember: false)
    @session[:user_id] = user.id
    @session[:remember] = remember if remember
  end

  # Sign out current user
  def sign_out
    @session.delete(:user_id)
    @session.delete(:admin_id)
    @session.delete(:remember)
  end

  # Get current user ID
  def current_user_id
    @session[:user_id]
  end

  # Get current admin ID (for impersonation)
  def current_admin_id
    @session[:admin_id]
  end

  # Check if currently impersonating
  def impersonating?
    current_admin_id.present?
  end

  # Start impersonating a user
  def start_impersonation(admin:, target_user:)
    @session[:admin_id] = admin.id
    @session[:user_id] = target_user.id
  end

  # Stop impersonating and return to admin account
  def stop_impersonation
    return nil unless impersonating?

    admin_id = current_admin_id
    @session[:user_id] = admin_id
    @session.delete(:admin_id)

    User.find_by(id: admin_id)
  end

  # Expire old sessions for a user
  def self.expire_old_sessions(user, keep_session_id: nil)
    user.user_sessions.where.not(id: keep_session_id).destroy_all
  end

  # Clean up expired sessions globally
  def self.cleanup_expired_sessions
    User::Session.where("expires_at < ?", Time.current).destroy_all
  end

  # Get active sessions for a user
  def self.active_sessions(user)
    user.user_sessions.where("expires_at > ?", Time.current).order(last_seen_at: :desc)
  end

end
