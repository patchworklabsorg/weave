# frozen_string_literal: true

class AuthController < ApplicationController
  skip_before_action :authenticate_user!, only: [:login, :new_session, :password_login, :oauth_login, :send_magic_link, :magic_link_login]

  layout "sessions", only: [:new_session, :password_login, :oauth_login]

  def new_session
    redirect_to root_path if current_user
    @user = User.new
  end

  def password_login
    redirect_to root_path if current_user
    @user = User.new
    @is_password_login = true
  end

  def oauth_login
    redirect_to root_path if current_user

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

    user = User.find_by(email: email.downcase)

    # Password login flow (from /login/pw) - ADMIN ONLY
    if user_password.present?
      if user && user.authenticate(user_password)
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
    if user.send_magic_link
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

    user = User.find_by(email: email&.downcase)

    if user.nil?
      # Don't reveal whether the email exists or not for security
      respond_to do |format|
        format.html { redirect_to login_path, notice: "If an account with this email exists, a magic link has been sent." }
        format.json { render json: { message: "If an account with this email exists, a magic link has been sent." }, status: :ok }
      end
      return
    end

    if user.send_magic_link
      respond_to do |format|
        format.html { redirect_to login_path, notice: "Magic link sent! Check your email to continue." }
        format.json { render json: { message: "Magic link sent to your email" }, status: :ok }
      end
    else
      handle_login_error("Failed to send magic link", email)
    end
  end

  def magic_link_login
    token = params[:token]

    if token.blank?
      redirect_to login_path, alert: "Invalid magic link"
      return
    end

    user = User.find_by(magic_link_token: token)

    if user.nil?
      Rails.logger.info "Magic link login failed: No user found (token hash: #{Digest::SHA256.hexdigest(token)[0..8]})"
      redirect_to login_path, alert: "Invalid or expired magic link"
      return
    end

    Rails.logger.info "Magic link validation for user #{user.email}: token_present=#{user.magic_link_token.present?}, expires_at=#{user.magic_link_expires_at}, current_time=#{Time.current}, used_at=#{user.magic_link_used_at}"

    if !user.magic_link_valid?
      redirect_to login_path, alert: "Invalid or expired magic link"
      return
    end

    if user.consume_magic_link_token!
      complete_login(user)
    else
      redirect_to login_path, alert: "Failed to process magic link"
    end
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

  def complete_login(user)
    session[:user_id] = user.id

    respond_to do |format|
      format.html { redirect_to root_path, notice: "Logged in successfully" }
      format.json { render json: { user: UserSerializer.render(user) }, status: :ok }
    end
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
