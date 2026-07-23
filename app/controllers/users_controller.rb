# frozen_string_literal: true

# app/controllers/users_controller.rb
class UsersController < ApplicationController
  skip_before_action :authenticate_user!, only: [:new, :create, :username_conflict]

  layout "sessions", only: [:new]
  def new
    redirect_to(root_path) and return if current_user

    @user = User.new
  end

  def create
    begin
      user_attrs = sanitized_user_params

      # Generate a random secure password for non-admin users
      # They will only use magic links to login
      random_password = User.generate_secure_password
      user_attrs[:password] = random_password
      user_attrs[:password_confirmation] = random_password

      @user = User.new(user_attrs)
    rescue ActiveRecord::RecordInvalid => e
      @user = e.record
      render :new, status: :unprocessable_entity
      return
    end

    if @user.save
      redirect_to email_confirmation_path, notice: "Account created! Please check your email to verify your account."
    else
      # Check if this is a username conflict error
      if @user.errors[:base]&.any? { |message| message.include?("snafu") }
        redirect_to username_conflict_path
      else
        render :new, status: :unprocessable_entity
      end
    end
  end

  def username_conflict
    render "errors/username_conflict", layout: false
  end

  def show
    @user = current_user
  end

  def sessions
    @user = current_user
    @sessions = @user.user_sessions.order(created_at: :desc)
  end

  def edit
    @user = current_user
  end

  # Revoke a single session belonging to the current user.
  def destroy_session
    user_session = current_user.user_sessions.find_by(id: resolve_session_id(params[:id]))

    if user_session.nil?
      redirect_to profile_sessions_path, alert: "Session not found."
      return
    end

    if user_session == current_user_session
      redirect_to profile_sessions_path, alert: "You cannot revoke your current session from here. Use Sign out instead."
      return
    end

    user_session.update!(signed_out_at: Time.current, expiration_at: Time.current)
    redirect_to profile_sessions_path, notice: "Session revoked."
  end

  # Sign out of every session except the one making this request.
  def destroy_all_sessions
    current = current_user_session

    current_user.user_sessions.not_expired.where.not(id: current&.id).find_each do |user_session|
      user_session.update!(signed_out_at: Time.current, expiration_at: Time.current)
    end

    redirect_to profile_sessions_path, notice: "Signed out of all other sessions."
  end

  def update
    @user = current_user
    begin
      # Handle cropped image data if present
      if params[:user][:cropped_image_data].present?
        process_cropped_image(params[:user][:cropped_image_data])
      end

      sanitized = sanitized_user_params.except(:cropped_image_data)
      if sanitized[:billing_same_as_shipping] == "1" && sanitized[:billing_address_attributes].blank?
        sanitized[:billing_address_attributes] = sanitized[:shipping_address_attributes].dup
        sanitized[:billing_address_attributes].delete(:id) if sanitized[:billing_address_attributes][:id]
      end

      if @user.update(sanitized)
        redirect_to root_path, notice: "Account successfully updated!"
      else
        render :edit, status: :unprocessable_entity
      end
    rescue ActiveRecord::RecordInvalid => e
      @user = e.record
      render :edit, status: :unprocessable_entity
    end
  end


  private

  # Sessions are addressed by their encoded public id (or hashid) in URLs.
  # Resolve that back to the primary key so we can scope to the current user.
  def resolve_session_id(param)
    User::Session.find(param.to_s).id
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def sanitized_user_params
    # Non-admins cannot set passwords - they use magic links only
    # Only permit password params for existing admin users updating their profile
    password_fields = if current_user&.admin?
                        [:password, :password_confirmation]
                      else
                        []
                      end

    permitted_params = params.require(:user).permit(:first_name, :last_name, :legal_first_name, :legal_last_name, :email, :pronouns, :phone_number, :birthday, :cropped_image_data, :billing_same_as_shipping,
                                                    *password_fields,
                                                    shipping_address_attributes: Address::PARAMS + [:id],
                                                    billing_address_attributes: Address::PARAMS + [:id])

    # Simple sanitization: strip whitespace from string fields.
    # Keys are symbolized so the symbol-keyed lookups below (e.g. :birthday,
    # :email, :billing_same_as_shipping) resolve correctly.
    sanitized = {}
    permitted_params.each do |key, value|
      if value.is_a?(String)
        sanitized[key.to_sym] = value.strip
      else
        # Handle file uploads and other non-string parameters
        sanitized[key.to_sym] = value
      end
    end

    # Special handling for email - ensure it's properly formatted
    if sanitized[:email].present?
      sanitized[:email] = sanitized[:email].downcase.strip
    end

    # Prevent birthday changes if already set (only allow initial setting).
    # Once a birthday exists, ignore any submitted birthday value, including an
    # attempt to clear it.
    if @user&.birthday.present? && sanitized.key?(:birthday)
      sanitized.delete(:birthday)
    end

    sanitized
  end

  def user_params
    params.require(:user).permit(:first_name, :last_name, :legal_first_name, :legal_last_name, :email, :pronouns, :password, :password_confirmation, :birthday,
                                 shipping_address_attributes: UserAddress::PARAMS + [:id],
                                 billing_address_attributes: UserAddress::PARAMS + [:id])
  end

end
