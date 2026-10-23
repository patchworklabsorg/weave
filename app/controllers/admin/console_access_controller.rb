# frozen_string_literal: true

# A person signs their production console in here. The console shows a code;
# the person enters it, checks the console, and confirms that it is theirs.
# The console then records its session under that person. See
# docs/CONSOLE_ACCESS.md.
class Admin::ConsoleAccessController < Admin::BaseController
  RECENT_LIMIT = 20

  before_action :refuse_impersonation
  rate_limit to: 10, within: 1.minute, only: %i[lookup confirm],
             with: -> { redirect_to admin_console_access_path, alert: "Too many attempts. Wait a minute, then try again." }

  def show
    @recent = ConsoleAccessRequest.includes(:user).order(created_at: :desc).limit(RECENT_LIMIT)
  end

  def lookup
    @console_request = ConsoleAccessRequest.find_pending_by_code(params[:code])
    return redirect_to(admin_console_access_path, alert: no_request_message) unless @console_request

    @code = params[:code].to_s.strip
  end

  def confirm
    console_request = ConsoleAccessRequest.find_pending_by_code(params[:code])
    return redirect_to(admin_console_access_path, alert: no_request_message) unless console_request

    if params[:answer] == "mine" && console_request.confirm!(by: current_user, ip: request.remote_ip)
      redirect_to admin_console_access_path, notice: "Done. The console opens in a few seconds, under your name."
    elsif params[:answer] == "not_mine" && console_request.reject!(by: current_user, ip: request.remote_ip)
      redirect_to admin_console_access_path, notice: "The console stops."
    else
      redirect_to admin_console_access_path, alert: no_request_message
    end
  end

  private

  def no_request_message
    "No open console has this code. A code expires after #{ConsoleAccessRequest::EXPIRATION.inspect}."
  end

  # The record names the person who is signed in. During impersonation that is
  # not the person at the keyboard.
  def refuse_impersonation
    return unless impersonating?

    redirect_to admin_root_path, alert: "Stop impersonating before you sign in a console."
  end

end
