# frozen_string_literal: true

# Reminds Slack guests who are stuck in #start-here (User.stuck_in_start_here)
# to accept the code of conduct. They got the welcome DM when they joined but
# never pressed the button, so they can't see the other channels.
#
# Each guest gets one reminder, as a Slack DM and an email (see
# CodeOfConductRequestJob, reason :onboarding), WAIT after they joined. The
# request sets slack_coc_requested_at, so a later run skips them.
#
# Runs daily from config/recurring.yml. Does nothing until the
# start_here_nudge Flipper flag is on.
class NudgeStuckSlackGuestsJob < ApplicationJob
  queue_as :low

  WAIT = 2.days

  def perform
    return unless Flipper.enabled?(:start_here_nudge)

    service = SlackService.new
    return unless service.configured?

    self.class.candidates.find_each do |user|
      # A deleted Slack account is also `pending` in Weave. Don't email
      # someone who left.
      next unless service.active_guest?(user.slack_id)

      CodeOfConductRequestJob.perform_later(user.id, reason: :onboarding)
    rescue Slack::Web::Api::Errors::SlackError => e
      Rails.logger.error "Failed to check Slack guest #{user.slack_id}: #{e.message}"
    end
  end

  # A missing slack_joined_at means an old account, so it counts as joined
  # long ago.
  def self.candidates
    User.where(status: "active", locked_at: nil).merge(User.stuck_in_start_here)
        .where(slack_coc_requested_at: nil)
        .where("users.slack_joined_at IS NULL OR users.slack_joined_at <= ?", WAIT.ago)
  end

end
