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

    self.class.candidates.find_each do |user|
      CodeOfConductRequestJob.perform_later(user.id, reason: :onboarding)
    end
  end

  # A missing slack_joined_at means an old account, so it counts as joined
  # long ago.
  def self.candidates
    User.stuck_in_start_here
        .where(slack_coc_requested_at: nil)
        .where("users.slack_joined_at IS NULL OR users.slack_joined_at <= ?", WAIT.ago)
  end

end
