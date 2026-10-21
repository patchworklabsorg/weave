# frozen_string_literal: true

# A person whose AD password expired or must change (AD 532 or 773) can't
# bind, so they can't sign in. AuthController sends them here after AD has
# confirmed the old password. They type the old password again with a new
# one, and Weave sends an AD "change" as the service account.
#
# The session holds only the user id and the time, for WINDOW. Nobody is
# signed in here. After the change the person signs in with the new password,
# and a pending OAuth authorization (for example Google) continues.
class ExpiredPasswordsController < ApplicationController
  include PasswordChangeMessages

  SESSION_KEY = :expired_password_change
  WINDOW = 10.minutes

  skip_before_action :authenticate_user!
  before_action :load_pending_user

  layout "sessions"

  def show
  end

  def update
    new_password = params[:password].to_s
    problem = new_password_problem(new_password, params[:password_confirmation].to_s)
    return render_problem(problem) if problem

    current = params[:current_password].to_s
    return render_problem(:current_missing) if current.blank?

    status = DirectoryPasswords.change(@user, current: current, new: new_password)
    if status == :ok
      session.delete(SESSION_KEY)
      redirect_to password_login_path, notice: "Your password was changed. Sign in with the new password."
    else
      render_problem(status)
    end
  end

  private

  def load_pending_user
    pending = session[SESSION_KEY]
    started_at = pending.is_a?(Hash) ? pending["at"].to_i : 0
    @user = User.find_by(id: pending["user_id"]) if started_at > WINDOW.ago.to_i

    return if @user&.can_authenticate?

    session.delete(SESSION_KEY)
    redirect_to password_login_path, alert: "Sign in again to change your expired password."
  end

  def render_problem(status)
    flash.now[:alert] = password_change_message(status)
    render :show, status: :unprocessable_entity
  end

end
