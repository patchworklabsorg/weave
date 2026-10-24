# frozen_string_literal: true

# The dormancy cutoff (config/kyc/data_retention.yml, dormancy). An account
# with no sign-in for inactive_years goes to the deletion pipeline, through
# the same human review as a member's request.
#
# - Warning emails go warning_days_before the cutoff (60 and 7 days). When
#   more than one is due, only the most urgent one goes.
# - The request is made only after the last warning went out at least that
#   many days before. So a member always has the full last window to sign in.
# - Any sign-in resets the clock: User#last_active_at moves, the old
#   warnings stop counting, and an open dormancy request is cancelled.
class DormancyJob < ApplicationJob
  queue_as :low

  def perform
    cancel_requests_after_sign_in
    candidates.find_each { |user| check(user) }
  end

  private

  def cancel_requests_after_sign_in
    DeletionRequest.where(source: "dormancy", status: %w[pending_review approved]).includes(:user).find_each do |request|
      request.cancel! if request.user && request.user.last_active_at > request.requested_at
    end
  end

  # Users whose last activity is before the first warning.
  def candidates
    first_warning = (DataRetention.dormancy_cutoff - DataRetention.dormancy_warning_days.max.days).ago
    last_activity = "GREATEST(users.created_at, COALESCE(MAX(user_sessions.last_seen_at), users.created_at), " \
                    "COALESCE(MAX(user_sessions.created_at), users.created_at))"
    ids = User.left_joins(:user_sessions).group(:id).having("#{last_activity} <= ?", first_warning).pluck(:id)
    User.where(id: ids).where.not(id: DeletionRequest.unfinished.where.not(user_id: nil).select(:user_id))
  end

  def check(user)
    last_active = user.last_active_at
    deadline = last_active + DataRetention.dormancy_cutoff
    now = Time.current
    final_days = DataRetention.dormancy_warning_days.min
    warnings = user.dormancy_warnings.where(last_active_at: last_active)

    if now >= deadline
      final = warnings.where(days_before: ..final_days).minimum(:sent_at)
      if final.nil?
        send_warning(user, final_days, last_active, now + final_days.days)
      elsif final <= final_days.days.ago
        DeletionReview.request!(user, source: "dormancy")
      end
      return
    end

    due = DataRetention.dormancy_warning_days.select { |days| now >= deadline - days.days }.min
    return if due.nil? || warnings.exists?(days_before: ..due)

    send_warning(user, due, last_active, deadline)
  end

  def send_warning(user, days_before, last_active, deadline)
    user.dormancy_warnings.create!(days_before:, last_active_at: last_active, sent_at: Time.current)
    DataHandlingMailer.dormancy_warning(user, days_before:, deadline:).deliver_later
  end

end
