# frozen_string_literal: true

class AuthController < ApplicationController
  include OauthClientRedirectOrigins
  include PasskeyChallenges

  # Signing in while an OAuth authorization is pending ends in a redirect chain
  # (login → /oauth/authorize → the client's redirect_uri) when the user already
  # granted consent. form-action applies to that whole chain, so the sign-in forms
  # must allow the pending client's registered origins, and only those. See
  # OauthClientRedirectOrigins.
  content_security_policy do |policy|
    policy.form_action(:self, *pending_oauth_client_origins)
  end
  skip_before_action :authenticate_user!, only: [:login, :new_session, :oauth_login, :send_magic_link, :magic_link_login, :confirm_magic_link, :check_password_login, :passkey_options, :passkey_login, :logout]
  # A user with an unverified email must still be able to log out. Under
  # authenticate_user! the logout went to the email confirmation page instead.
  before_action :authenticate_user_without_email_verification!, only: [:logout]

  layout "sessions", only: [:new_session, :oauth_login, :magic_link_login]

  # Why a link was refused, phrased so the reader knows which of these it is.
  # The old flow collapsed all of them into "Invalid or expired magic link",
  # which sent people looking for an expiry problem they didn't have.
  MAGIC_LINK_ERRORS = {
    missing: "That sign-in link is incomplete. Request a new one below.",
    unknown: "We don't recognize that sign-in link. It may have been copied incompletely — request a new one below.",
    used: "That sign-in link has already been used. Request a new one below.",
    expired: "That sign-in link has expired. Request a new one below.",
    inactive: "This account can't sign in right now. Contact an administrator for help."
  }.freeze

  PASSKEY_ERRORS = {
    expired: "The passkey request timed out. Try again.",
    invalid: "We couldn't verify that passkey. Try again, or sign in with an email link.",
    unknown: "That passkey isn't set up for Weave. Sign in with an email link, then add it from your profile.",
    compromised: "That passkey is turned off because it may have been copied. Sign in with an email link, then remove it from your profile.",
    inactive: MAGIC_LINK_ERRORS[:inactive]
  }.freeze

  def new_session
    redirect_to(root_path) and return if current_user

    @user = User.new
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

    # Password login flow, for admins and users linked to Active Directory
    # (see DirectoryPasswords.password_sign_in?). Linked users check their AD
    # password. Admins with no AD account keep Weave's own password check.
    if user_password.present?
      password_login_for(user, user_password, email)
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
    if user.send_magic_link(requested_ip: request.remote_ip, return_to: session[:oauth_return_to])
      respond_to do |format|
        format.html { redirect_to login_path, notice: "Check your email for the sign-in link." }
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

    if user.send_magic_link(requested_ip: request.remote_ip, return_to: session[:oauth_return_to])
      respond_to do |format|
        format.html { redirect_to login_path, notice: "Check your email for the sign-in link." }
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
    # wanted. A link that is still live and was asked for during an authorize
    # request goes on to that request, so a phone that is already signed in
    # still resumes it.
    if current_user == link.user
      redirect_to((link.live? && link.return_to) || root_path)
      return
    end

    if (reason = link.rejection_reason)
      reject_magic_link(reason, link.user)
      return
    end

    @magic_link_user = link.user
    # Someone else can ask for a link to this address while an authorize
    # request is pending in their browser. Name the app, so the owner of the
    # address sees where the link goes before they sign in.
    @continues_to = link.pending_application&.name
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
    # A link opened in another browser finds no authorize request in this
    # session, or an old one that was never finished. Resume the one the link
    # was asked for in (see User::MagicLink): it is the newest intent.
    session[:oauth_return_to] = link.return_to if link.return_to.present?
    complete_login(link.user)
  end


  # Step one of passkey sign-in: a challenge for the browser to have a passkey
  # sign. The login page asks for one when it loads (for passkey autofill) and
  # again when the "Sign in with a passkey" button is pressed.
  def passkey_options
    options = PasskeyAuthentication.sign_in_options
    store_passkey_challenge(:sign_in, options.challenge)
    render json: options
  end

  # Step two: the signed challenge. A verified passkey is a full sign-in, so
  # this ends like a magic link does, including the return to a pending OAuth
  # authorization.
  def passkey_login
    passkey = PasskeyAuthentication.authenticate!(
      credential: params[:credential].to_s,
      challenge: take_passkey_challenge(:sign_in)
    )
    complete_login(passkey.user)
  rescue PasskeyAuthentication::Failure => e
    message = PASSKEY_ERRORS.fetch(e.reason)
    respond_to do |format|
      format.html { redirect_to login_path, alert: message }
      format.json { render json: { error: message }, status: :unauthorized }
    end
  end

  # Called by the login form JS to decide whether to show the password field.
  # Admins and users linked to Active Directory authenticate with a password;
  # everyone else uses magic links. This reads only Weave's database: it
  # never asks AD, so it can't be used to probe the directory.
  def check_password_login
    email = params[:email].to_s.strip.downcase
    user = User.find_for_any_email(email) if email.present?
    password_enabled = user.present? && DirectoryPasswords.password_sign_in?(user)

    render json: { password_login_enabled: password_enabled, password_required: password_enabled }
  end

  def logout
    if session[:admin_id]
      end_impersonation("logged_out")
      original_admin = User.find_by(id: session[:admin_id])

      # The admin who started impersonating was deleted in the meantime, so
      # there is no account to return to. Sign out completely.
      if original_admin.nil?
        reset_session
        respond_to do |format|
          format.html { redirect_to login_path, notice: "Signed out." }
          format.json { render json: { message: "Logged out successfully" } }
        end
        return
      end

      session[:user_id] = session[:admin_id]
      session.delete(:admin_id)
      respond_to do |format|
        format.html { redirect_to admin_users_path, notice: "Returned to admin account" }
        format.json { render json: { message: "Returned to admin account", user: UserSerializer.render(original_admin) } }
      end
    else
      # Close the user_sessions row too. Deleting session[:user_id] alone left
      # the row live, so a copy of the cookie taken before logout stayed
      # signed in until the row expired.
      sign_out
      respond_to do |format|
        format.html { redirect_to login_path, notice: "Signed out." }
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

  # The magic link confirmation page asks about the link itself, because a
  # link opened in another browser brings its authorize request with it (see
  # #confirm_magic_link), and that request wins over the session's. The
  # page's form must allow that client.
  def pending_oauth_client_origins
    link_application = User::MagicLink.for_token(params[:token])&.pending_application if action_name == "magic_link_login"

    if link_application
      redirect_origins_for(link_application)
    elsif session[:oauth_return_to].present? && session[:oauth_client_id].present?
      redirect_origins_for(Doorkeeper::Application.find_by(uid: session[:oauth_client_id]))
    else
      []
    end
  end

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

  # Messages for password sign-in. Wrong password and an unknown email read
  # the same, so the form does not reveal who has an account. A disabled or
  # expired AD account reads the same too (see DirectoryPasswords).
  PASSWORD_ERRORS = {
    invalid: "Invalid email or password",
    locked: "Too many failed sign-in attempts. Wait 15 minutes, or sign in with an email link.",
    throttled: "Too many failed sign-in attempts. Wait 15 minutes, or sign in with an email link.",
    unlinked: "This account can't sign in with a password. Contact an administrator for help.",
    unavailable: "Password sign-in is not available now. Sign in with an email link, or try again later."
  }.freeze

  def password_login_for(user, password, email)
    # Don't ask AD about accounts Weave would refuse anyway. A user who is not
    # an admin and not linked yet gets the same message as a wrong password,
    # so the form does not tell who may use one.
    return handle_login_error(PASSWORD_ERRORS[:invalid], email) if user.nil? || !user.can_authenticate? || !DirectoryPasswords.password_sign_in?(user)

    case DirectoryPasswords.sign_in(user, password)
    when :authenticated
      complete_login(user)
    when :not_directory
      local_password_login(user, password, email)
    when :must_change_password
      start_expired_password_change(user)
    when :invalid then handle_login_error(PASSWORD_ERRORS[:invalid], email)
    when :locked then handle_login_error(PASSWORD_ERRORS[:locked], email)
    when :throttled then handle_login_error(PASSWORD_ERRORS[:throttled], email)
    when :unlinked then handle_login_error(PASSWORD_ERRORS[:unlinked], email)
    else handle_login_error(PASSWORD_ERRORS[:unavailable], email)
    end
  end

  # Weave's own password, for admins with no AD account. The admin check
  # repeats the gate in password_login_for, with the same message.
  def local_password_login(user, password, email)
    if user.admin? && user.authenticate(password)
      complete_login(user)
    else
      handle_login_error(PASSWORD_ERRORS[:invalid], email)
    end
  end

  # AD accepted the password but it expired or must change (AD 532 or 773).
  # The user proves the old password again on the next page, so the session
  # keeps only who it is and when, never the password.
  def start_expired_password_change(user)
    session[ExpiredPasswordsController::SESSION_KEY] = { "user_id" => user.id, "at" => Time.current.to_i }
    respond_to do |format|
      format.html { redirect_to expired_password_path, notice: "Your password has expired. Choose a new one to continue." }
      format.json { render json: { error: "password_change_required", redirect_to: expired_password_path }, status: :unauthorized }
    end
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

    LinkDirectoryAccountJob.perform_later(user.id) if DirectoryPasswords.enabled? && !DirectoryPasswords.linked?(user)

    destination = post_login_destination

    respond_to do |format|
      format.html { redirect_to destination, notice: "Signed in." }
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
  #
  # Otherwise, return to the protected page that asked for the sign-in (see
  # ReturnAfterSignIn). Both keys are taken out, so neither one outlives this
  # sign-in.
  def post_login_destination
    oauth_return_to = session.delete(:oauth_return_to).to_s
    return_to = take_return_path
    return oauth_return_to if oauth_return_to.start_with?("/oauth/authorize")

    return_to || root_path
  end


  def handle_login_error(message, email)
    respond_to do |format|
      format.turbo_stream do
        flash.now[:alert] = message
        @user = User.new(email: email)
        render turbo_stream: [
          turbo_stream.update("flash", partial: "shared/flash"),
          turbo_stream.update("login_form", partial: "auth/login_form", locals: { user: @user })
        ], status: :unprocessable_content
      end
      format.html do
        flash.now[:alert] = message
        @user = User.new(email: email)
        render :new_session, status: :unprocessable_content
      end
      format.json { render json: { error: message }, status: :unauthorized }
    end
  end

  def user_params
    params.expect(user: [:email, :username, :first_name, :last_name, :role])
  end

end
