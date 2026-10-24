# frozen_string_literal: true

# The board report of break-glass access for one month (see
# BreakGlassReport). The identity team and board members can read it.
# BreakGlassBoardReportJob emails it to the board each month.
class Admin::BreakGlassReportsController < Admin::BaseController
  before_action :require_identity_team_or_board

  def show
    month = begin
      Date.iso8601(params[:month].to_s)
    rescue Date::Error
      Date.current
    end
    @report = BreakGlassReport.new(month)
  end

  private

  def require_identity_team_or_board
    return if current_user.identity_team || current_user.is_board

    redirect_to admin_root_path, alert: "Only the identity team and the board can open this report."
  end

end
