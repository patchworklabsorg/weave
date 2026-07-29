# frozen_string_literal: true

class AuthController < ApplicationController
  skip_before_action :authenticate_user!, only: [:login, :new_session, :password_login, :oauth_login, :send_magic_link, :magic_link_login, :confirm_magic_link, :check_password_login]

  layout "sessions", only: [:new_session, :password_login, :oauth_login, :magic_link_login]

  # Why a link was refused, phrased so the reader knows which of these it is.
  # The old flow collapsed all of them into "Invalid or expired magic link",
  # which sent people looking for an expiry problem they didn't have.
  MAGIC_LINK_ERRORS = {
    missing: "That sign-in link is incomplete. Request a new one below.",
    unknown: "We don't recognize that sign-in link. It may have been copied incompletely — request a new one below.",
    used: "That sign-in link has already been used. Request a new one below.",
    expired: "That sign-in link has expired. Request a new one below."
  }.freeze

  def new_session
    redirect_to(root_path) and return if current_user

    @user = User.new
  end

  def password_login
    redirect_to(root_path) and return if current_user

    @user = User.new
    @is_password_login = true
  end

  def oauth_login
    redirect_to(root_path) and return if current_user

    # Check if this is a legitimate OAuth flow
    client_id = session[:oauth_client_id] || params[:client_id]
    if client_id.blank?
      # No client_id means this isn't part of an OAuth flow
      redirect_to login_path
      return
    end

    @user = User.new

    # Get OAuth client information
    @oauth_client_name = nil
    oauth_app = Doorkeeper::Application.find_by(uid: client_id)
    if oauth_app
      @oauth_client_name = oauth_app.name
    else
      # Invalid client_id, redirect to regular login
      redirect_to login_path
      return
    end
  end

  def login
    user_email = params.dig(:user, :email)
    user_password = params.dig(:user, :password)
    email = user_email.to_s.strip

    if email.blank?
      handle_login_error("Email is required", email)
      return
    end

    user = User.find_for_any_email(email)

    # Password login flow (from /login/pw) - ADMIN ONLY
    if user_password.present?
      if user&.authenticate(user_password)
        # Only allow password login for admin users
        if user.admin?
          complete_login(user)
        else
          handle_login_error("Password login is only available for administrators. Please use the magic link.", email)
        end
      else
        handle_login_error("Invalid email or password", email)
      end
      return
    end

    # Magic link flow - handle non-existent emails gracefully
    if user.nil?
      # Don't reveal that email doesn't exist - show success message anyway
      respond_to do |format|
        format.html { redirect_to login_path, notice: "If an account with this email exists, a magic link has been sent." }
        format.json { render json: { message: "If an account with this email exists, a magic link has been sent." }, status: :ok }
      end
      return
    end

    # Send magic link to existing user
    if user.send_magic_link(requested_ip: request.remote_ip)
      respond_to do |format|
        format.html { redirect_to login_path, notice: "Magic link sent! Check your email to continue." }
        format.json { render json: { message: "Magic link sent to your email" }, status: :ok }
      end
    else
      handle_login_error("Failed to send magic link", email)
    end
  end

  def send_magic_link
    user_email = params.dig(:user, :email) || params[:email]
    email = user_email.to_s.strip

    if email.blank?
      handle_login_error("Email is required", email)
      return
    end

    user = User.find_for_any_email(email)

    if user.nil?
      # Don't reveal whether the email exists or not for security
      respond_to do |format|
        format.html { redirect_to login_path, notice: "If an account with this email exists, a magic link has been sent." }
        format.json { render json: { message: "If an account with this email exists, a magic link has been sent." }, status: :ok }
      end
      return
    end

    if user.send_magic_link(requested_ip: request.remote_ip)
      respond_to do |format|
        format.html { redirect_to login_path, notice: "Magic link sent! Check your email to continue." }
        format.json { render json: { message: "Magic link sent to your email" }, status: :ok }
      end
    else
      handle_login_error("Failed to send magic link", email)
    end
  end

  # Deliberately does not sign anyone in. Anything that follows links in an
  # inbox — Outlook Safe Links, Proofpoint, Slack unfurls, browser prefetch —
  # issues a GET here, and when this action consumed the token those fetches
  # burned the link before its owner ever clicked. Signing in requires the POST
  # below, which only a human pressing the button produces.
  def magic_link_login
    @token = params[:token]
    link = find_magic_link(@token)
    return if link.nil?

    # Re-opening a link you already used in this browser (back button, second
    # click) shouldn't read as an error — you're signed in, which is what you
    # wanted.
    if current_user == link.user
      redirect_to root_path
      return
    end

    if (reason = link.rejection_reason)
      reject_magic_link(reason, link.user)
      return
    end

    @magic_link_user = link.user
  end

  def confirm_magic_link
    link = find_magic_link(params[:token])
    return if link.nil?

    if (reason = link.rejection_reason)
      reject_magic_link(reason, link.user)
      return
    end

    # consume! is the atomic claim — a false return means something else got
    # there first in the gap between the check above and here.
    unless link.consume!
      reject_magic_link(:used, link.user)
      return
    end

    link.user.confirm_email_from_magic_link!
    complete_login(link.user)
  end


  # Called by the login form JS to decide whether to show the password field.
  # Admins authenticate with a password; everyone else uses magic links.
  def check_password_login
    email = params[:email].to_s.strip.downcase
    user = User.find_for_any_email(email) if email.present?
    password_enabled = user&.admin? || false

    render json: { password_login_enabled: password_enabled, password_required: password_enabled }
  end

  def logout
    if session[:admin_id]
      original_admin = User.find(session[:admin_id])
      session[:user_id] = session[:admin_id]
      session.delete(:admin_id)
      respond_to do |format|
        format.html { redirect_to admin_users_path, notice: "Returned to admin account" }
        format.json { render json: { message: "Returned to admin account", user: UserSerializer.render(original_admin) } }
      end
    else
      session.delete(:user_id)
      respond_to do |format|
        format.html { redirect_to login_path, notice: "Logged out successfully" }
        format.json { render json: { message: "Logged out successfully" } }
      end
    end
  end

  def me
    respond_to do |format|
      format.html { render :me }
      format.json { render json: { user: UserSerializer.render(current_user) } }
    end
  end

  private

  # Returns the link, or nil after having already redirected. Callers bail on nil.
  def find_magic_link(token)
    if token.blank?
      redirect_to login_path, alert: MAGIC_LINK_ERRORS[:missing]
      return nil
    end

    link = User::MagicLink.for_token(token)

    if link.nil?
      # Logged without the token so the line is safe to keep, but with enough to
      # correlate repeats from one mangled email.
      Rails.logger.info "Magic link rejected: unknown token (digest prefix: #{User::MagicLink.digest_for(token)[0, 8]})"
      redirect_to login_path, alert: MAGIC_LINK_ERRORS[:unknown]
      return nil
    end

    link
  end

  def reject_magic_link(reason, user)
    Rails.logger.info "Magic link rejected for #{user.email}: #{reason}"
    redirect_to login_path, alert: MAGIC_LINK_ERRORS.fetch(reason)
  end

  def complete_login(user)
    # Rotate the session id before establishing the login (session fixation),
    # preserving any in-progress OAuth context across the reset.
    reset_session_preserving_oauth
    session[:user_id] = user.id

    # Back the login with a user_sessions record so it can be validated (and
    # revoked) on subsequent requests.
    user.user_sessions.create!(
      session_token: session.id.to_s,
      expiration_at: user.session_duration_seconds.seconds.from_now,
      ip: request.remote_ip,
      last_seen_at: Time.zone.now,
      **session_device_attributes
    )

    destination = post_login_destination

    respond_to do |format|
      format.html { redirect_to destination, notice: "Logged in successfully" }
      format.json { render json: { user: UserSerializer.render(user) }, status: :ok }
    end
  end

  # Device metadata for a new session: browser/OS parsed from the user agent,
  # fingerprint and timezone from hidden fields the login forms fill in via JS
  # (blank when JS didn't run — the session is still created without them).
  def session_device_attributes
    browser = Browser.new(request.user_agent)

    {
      device_info: browser.known? ? "#{browser.name} #{browser.version}" : request.user_agent,
      os_info: browser.platform.unknown? ? nil : "#{browser.platform.name} #{browser.platform.version}",
      fingerprint: params[:fingerprint].to_s.first(255).presence,
      timezone: params[:timezone].to_s.first(64).presence
    }
  end

  # Resume an authorize request that sent the user here to sign in, rather than
  # dropping them on the dashboard. This matters most for magic links: signing in
  # means leaving for an email client and coming back on a fresh request, so
  # without this the client that started the flow waits for a callback that never
  # arrives.
  #
  # The value comes out of the session and goes straight into redirect_to, so
  # only a local /oauth/authorize path is honoured — anything else is discarded
  # rather than turned into an open redirect.
  def post_login_destination
    return_to = session.delete(:oauth_return_to).to_s
    return_to.start_with?("/oauth/authorize") ? return_to : root_path
  end


  def handle_login_error(message, email)
    respond_to do |format|
      format.turbo_stream do
        flash.now[:alert] = message
        @user = User.new(email: email)
        render turbo_stream: [
          turbo_stream.update("flash", partial: "shared/flash"),
          turbo_stream.update("login_form", partial: "auth/login_form", locals: { user: @user })
        ], status: :unprocessable_entity
      end
      format.html do
        flash.now[:alert] = message
        @user = User.new(email: email)
        render :new_session, status: :unprocessable_entity
      end
      format.json { render json: { error: message }, status: :unauthorized }
    end
  end

  def user_params
    params.expect(user: [:email, :username, :first_name, :last_name, :role])
  end

end
