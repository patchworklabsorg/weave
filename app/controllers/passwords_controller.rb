# frozen_string_literal: true

# The change-password page, /password. Google Workspace links here as the SSO
# profile's "Change password URL", so a person who arrives from Google without
# a Weave session signs in first and then comes back here (see
# AuthController#post_login_destination).
#
# For a user with an Active Directory account the new password goes to AD and
# nowhere else (see DirectoryPasswords):
# - With the current password, Weave sends an AD "change" (delete the old
#   value, add the new one), so AD applies its history rules.
# - Without it, a person who signed in during the last RESET_WINDOW (with an
#   email link or a passkey) can reset a forgotten password. Weave then sends
#   a replace as the service account.
# Admins without an AD account change their Weave password here. Other users
# have no password: they sign in with email links and passkeys.
class PasswordsController < ApplicationController
  include PasswordChangeMessages

  RESET_WINDOW = 15.minutes

  prepend_before_action :remember_return_to_password, only: :show
  before_action :load_mode

  def show
  end

  def update
    if impersonating?
      redirect_to password_path, alert: "You can't change a password while impersonating a user."
      return
    end

    new_password = params[:password].to_s
    problem = new_password_problem(new_password, params[:password_confirmation].to_s)
    return render_problem(problem) if problem

    case @mode
    when :directory then update_directory_password(new_password)
    when :local then update_local_password(new_password)
    else redirect_to password_path
    end
  end

  private

  # Only when nobody is signed in: authenticate_user! then sends the person
  # to the sign-in page, which brings them back here afterwards.
  def remember_return_to_password
    session[:return_to_password] = true if current_user.nil?
  end

  def load_mode
    @mode = password_mode
    @reset_allowed = @mode == :directory && recent_sign_in?
  end

  def password_mode
    return :directory if DirectoryPasswords.directory_user?(current_user)

    current_user.admin? ? :local : :none
  rescue ActiveDirectory::Unavailable
    :unavailable
  end

  def recent_sign_in?
    created_at = current_user_session&.created_at
    created_at.present? && created_at > RESET_WINDOW.ago
  end

  def update_directory_password(new_password)
    current = params[:current_password].to_s
    status =
      if current.present?
        DirectoryPasswords.change(current_user, current: current, new: new_password)
      elsif @reset_allowed
        DirectoryPasswords.reset(current_user, new_password)
      else
        return render_problem(:current_missing)
      end

    if status == :ok
      redirect_to password_path, notice: "Your password was changed. Use the new password the next time you sign in."
    else
      render_problem(status)
    end
  end

  def update_local_password(new_password)
    return render_problem(:invalid_current_password) unless current_user.authenticate(params[:current_password].to_s)

    if current_user.update(password: new_password, password_confirmation: new_password)
      redirect_to password_path, notice: "Your password was changed."
    else
      flash.now[:alert] = current_user.errors.full_messages.to_sentence
      render :show, status: :unprocessable_entity
    end
  end

  def render_problem(status)
    flash.now[:alert] = password_change_message(status)
    render :show, status: :unprocessable_entity
  end

end
