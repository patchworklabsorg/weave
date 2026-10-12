# frozen_string_literal: true

class UserAuthenticationService
  class AuthenticationError < StandardError; end

  def initialize(user)
    @user = user
  end

  # Authenticate user with password
  def authenticate_with_password(password)
    return false unless @user&.authenticate(password)

    @user
  end

  # Check if user can be impersonated
  def can_be_impersonated_by?(admin)
    return false unless admin&.can_impersonate?
    return false if @user == admin # Can't impersonate yourself
    return false if @user.owner? # Can't impersonate owners

    # Admins can impersonate users, superadmins can impersonate admins and users
    case admin.role
    when "owner", "superadmin"
      true
    when "admin"
      @user.user? # Admins can only impersonate regular users
    else
      false
    end
  end

end
