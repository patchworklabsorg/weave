# frozen_string_literal: true

# app/controllers/users_controller.rb
class UsersController < ApplicationController
  skip_before_action :authenticate_user!, only: [:new, :create, :username_conflict]

  layout "sessions", only: [:new]
  def new
    redirect_to root_path if current_user
    @user = User.new
  end

  def create
    begin
      user_attrs = sanitized_user_params

      # Generate a random secure password for non-admin users
      # They will only use magic links to login
      random_password = SecureRandom.urlsafe_base64(32)
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


  def sanitized_user_params
    # Non-admins cannot set passwords - they use magic links only
    # Only permit password params for existing admin users updating their profile
    password_fields = if current_user&.admin?
                        [:password, :password_confirmation]
                      else
                        []
                      end

    permitted_params = params.require(:user).permit(:first_name, :last_name, :email, :birthday, :cropped_image_data, :billing_same_as_shipping,
                                                    *password_fields,
                                                    shipping_address_attributes: Address::PARAMS + [:id],
                                                    billing_address_attributes: Address::PARAMS + [:id])

    # Simple sanitization: strip whitespace from string fields
    sanitized = {}
    permitted_params.each do |key, value|
      if value.is_a?(String)
        sanitized[key] = value.strip
      else
        # Handle file uploads and other non-string parameters
        sanitized[key] = value
      end
    end

    # Special handling for email - ensure it's properly formatted
    if sanitized[:email].present?
      sanitized[:email] = sanitized[:email].downcase.strip
    end

    # Prevent birthday changes if already set (only allow initial setting)
    if @user&.birthday.present? && sanitized[:birthday].present?
      sanitized.delete(:birthday)
    end

    sanitized
  end

  def user_params
    params.require(:user).permit(:first_name, :last_name, :email, :password, :password_confirmation, :birthday,
                                 shipping_address_attributes: UserAddress::PARAMS + [:id],
                                 billing_address_attributes: UserAddress::PARAMS + [:id])
  end

end
