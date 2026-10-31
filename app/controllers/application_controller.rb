# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # First, so it wraps every other callback. See the concern.
  include RecordsImpersonationActions
  include ReturnAfterSignIn
  # Authorization policies (app/policies). The policy user is current_user.
  include Pundit::Authorization

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  before_action :authenticate_user!
  before_action :track_user_session
  # Tells the permanent log of privileged attributes who acts in this request
  # (see PrivilegedChangeActor).
  around_action :attribute_privileged_changes

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  # allow_browser versions: :modern

  # before_action do
  #   # Disallow indexing
  # response.set_header("X-Robots-Tag", "noindex")
  # end

  def find_current_auditor
    current_user if current_user&.superadmin?
  end

  def not_found
    raise ActionController::RoutingError, "Not Found"
  end

  def confetti!(emojis: nil)
    flash[:confetti] = true
    flash[:confetti_emojis] = emojis.join(",") if emojis
  end

  private

  def user_not_authorized
    redirect_to profile_path, alert: "You are not allowed to do that."
  end

  # The person behind the request: during impersonation, the admin.
  def attribute_privileged_changes
    actor = impersonating? ? admin_user : current_user
    label = ("user #{actor.p_id}#{" impersonating #{current_user.p_id}" if impersonating? && current_user}" if actor)
    PrivilegedChangeActor.set!(actor:, label:)
    yield
  ensure
    begin
      PrivilegedChangeActor.clear!
    rescue ActiveRecord::StatementInvalid => error
      Rails.logger.warn("Could not clear the privileged change actor: #{error.class}")
    end
  end

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = load_authenticated_user
  end

  # Resolve and validate the currently authenticated user (see
  # SessionAuthenticator for what makes a session valid). When any check fails
  # we reset the session and treat the request as logged out.
  def load_authenticated_user
    return nil if session[:user_id].blank?

    SessionAuthenticator.new(session).user || terminate_invalid_session!
  end

  def terminate_invalid_session!
    reset_session
    nil
  end

  # Rotate the session id to defeat session fixation, carrying forward the small
  # set of pre-login keys that say where to go after sign-in.
  def reset_session_preserving_oauth
    preserved = {
      oauth_client_id: session[:oauth_client_id],
      oauth_return_to: session[:oauth_return_to],
      ReturnAfterSignIn::SESSION_KEY => session[ReturnAfterSignIn::SESSION_KEY]
    }.compact
    reset_session
    preserved.each { |key, value| session[key] = value }
  end

  # The user_sessions row behind this cookie. During impersonation it belongs
  # to the admin, who is the one actually signed in (see SessionAuthenticator).
  # Never creates a row: a cookie without one is not signed in.
  def current_user_session
    return @current_user_session if defined?(@current_user_session)

    owner = impersonating? ? admin_user : current_user
    @current_user_session = (owner.user_sessions.find_by(session_token: session.id.to_s) if owner && session.id)
  end

  # Closes the audit row that Admin::UsersController#impersonate opened.
  def end_impersonation(reason)
    impersonation_id = session.delete(:impersonation_id)
    Impersonation.find_by(id: impersonation_id)&.end!(reason) if impersonation_id
  end

  def impersonating?
    session[:admin_id].present?
  end

  def admin_user
    @admin_user ||= User.find_by(id: session[:admin_id]) if session[:admin_id]
  end

  def authenticate_user!
    unless current_user
      respond_to do |format|
        format.html do
          store_return_path
          flash[:alert] = "You need to sign in before continuing"
          redirect_to "/login"
        end
        format.json { render json: { error: "You need to sign in before continuing" }, status: :unauthorized }
      end
      return
    end

    return if current_user.email_verified?

    respond_to do |format|
      format.html do
        store_return_path
        flash[:alert] = "Please verify your email address before continuing"
        redirect_to email_confirmation_path
      end
      format.json { render json: { error: "Email verification required", redirect_to: email_confirmation_path }, status: :forbidden }
    end

  end

  def authenticate_user_without_email_verification!
    return if current_user

    respond_to do |format|
      format.html do
        store_return_path
        flash[:alert] = "You need to sign in before continuing"
        redirect_to "/login"
      end
      format.json { render json: { error: "You need to sign in before continuing" }, status: :unauthorized }
    end
  end

  def require_admin
    return if current_user&.admin?

    render json: { error: "You are not authorized to perform this action" }, status: :forbidden

  end

  def track_user_session
    return unless current_user_session

    current_user_session.touch_last_seen_at
  end

  def sign_out
    current_user_session&.update(signed_out_at: Time.current, expiration_at: Time.current)
    reset_session
  end

  def sign_out_of_all_sessions
    return unless current_user

    current_user.user_sessions.not_expired.each do |session|
      session.update!(signed_out_at: Time.current, expiration_at: Time.current)
    end
    reset_session
  end

  helper_method :current_user, :current_user_session, :impersonating?, :admin_user

  # Track papertrail edits to specific users
  before_action :set_paper_trail_whodunnit

  private

  # While an admin impersonates a user, record changes are the admin's: the
  # version names the admin and points to the impersonation, so the
  # Impersonation row shows everything the admin did.
  def user_for_paper_trail
    impersonating? ? session[:admin_id] : current_user&.id
  end

  def info_for_paper_trail
    impersonating? ? { impersonation_id: session[:impersonation_id] } : {}
  end

end
