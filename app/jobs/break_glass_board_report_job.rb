# frozen_string_literal: true

# Sends the board the break-glass report for the previous month (see
# BreakGlassReport). The report goes out every month, also when nothing
# happened, so a missing report is a sign too.
class BreakGlassBoardReportJob < ApplicationJob
  queue_as :low

  def perform(month = nil)
    month = month ? Date.iso8601(month) : Date.current.prev_month
    report = BreakGlassReport.new(month)

    User.board_members.where.not(email: nil).find_each do |member|
      next unless member.can_authenticate?

      BreakGlassMailer.board_report(member, report.month.iso8601).deliver_later
    end
  end

end
