# frozen_string_literal: true

# A superadmin approves a production console here. The console shows a code;
# the superadmin enters it, checks the request, and approves or denies it. The
# console then records its session under the approver. See
# docs/CONSOLE_ACCESS.md.
class Admin::ConsoleAccessController < Admin::BaseController
  RECENT_LIMIT = 20

  before_action :refuse_impersonation
  before_action :require_superadmin
  rate_limit to: 10, within: 1.minute, only: %i[lookup decide],
             with: -> { redirect_to admin_console_access_path, alert: "Too many attempts. Wait a minute, then try again." }

  def show
    @recent = ConsoleAccessRequest.includes(:decided_by).order(created_at: :desc).limit(RECENT_LIMIT)
  end

  def lookup
    @console_request = ConsoleAccessRequest.find_pending_by_code(params[:code])
    return redirect_to(admin_console_access_path, alert: no_request_message) unless @console_request

    @code = params[:code].to_s.strip
  end

  def decide
    console_request = ConsoleAccessRequest.find_pending_by_code(params[:code])
    return redirect_to(admin_console_access_path, alert: no_request_message) unless console_request

    if params[:decision] == "approve" && console_request.approve!(by: current_user, ip: request.remote_ip)
      redirect_to admin_console_access_path, notice: "Approved. The console opens in a few seconds."
    elsif params[:decision] == "deny" && console_request.deny!(by: current_user, ip: request.remote_ip)
      redirect_to admin_console_access_path, notice: "Denied. The console stops."
    else
      redirect_to admin_console_access_path, alert: no_request_message
    end
  end

  private

  def no_request_message
    "No open console request has this code. A code expires after #{ConsoleAccessRequest::EXPIRATION.inspect}."
  end

  # The approval names the person who is signed in. During impersonation that
  # is not the person at the keyboard.
  def refuse_impersonation
    return unless impersonating?

    redirect_to admin_root_path, alert: "Stop impersonating before you approve a console."
  end

  def require_superadmin
    return if current_user.superadmin?

    redirect_to admin_root_path, alert: "Only a superadmin can approve a console."
  end

end
