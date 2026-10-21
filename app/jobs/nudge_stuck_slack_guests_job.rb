# frozen_string_literal: true

# Reminds Slack guests who are stuck in #start-here (User.stuck_in_start_here)
# to accept the code of conduct. They got the welcome DM when they joined but
# never pressed the button, so they can't see the other channels.
#
# Each guest gets one reminder, as a Slack DM and an email (see
# CodeOfConductRequestJob, reason :onboarding). The request sets
# slack_coc_requested_at, so a later run skips them.
#
# The daily run (config/recurring.yml) covers guests who joined between WAIT
# and WINDOW ago. slack_joined_at is only approximate (the Slack sync sets it
# from the profile's `updated` time), so the window keeps the daily run from
# reaching old accounts. To remind older guests once, preview and run by hand:
#
#   NudgeStuckSlackGuestsJob.candidates(since: nil).count
#   NudgeStuckSlackGuestsJob.perform_now(since: nil)
class NudgeStuckSlackGuestsJob < ApplicationJob
  queue_as :low

  WAIT = 2.days
  WINDOW = 14.days
  # Spaces the DMs out to stay under Slack's chat.postMessage rate limit, like
  # the slack:coc rake tasks.
  SPACING = 2.seconds

  def perform(since: WINDOW.ago)
    service = SlackService.new
    return unless service.configured?

    index = 0
    self.class.candidates(since:).find_each do |user|
      # Weave can't send these people to the accept step yet (see
      # User#slack_onboarding_step), so a reminder would not help.
      next if user.guardian_consent_missing?
      # A deleted Slack account is also `pending` in Weave. Don't email
      # someone who left.
      next unless service.active_guest?(user.slack_id)

      CodeOfConductRequestJob.set(wait: index * SPACING).perform_later(user.id, reason: :onboarding)
      index += 1
    rescue Slack::Web::Api::Errors::SlackError => e
      Rails.logger.error "Failed to check Slack guest #{user.slack_id}: #{e.message}"
    end
  end

  # since: nil drops the lower bound on slack_joined_at.
  def self.candidates(since: WINDOW.ago)
    scope = User.where(status: "active", locked_at: nil).merge(User.stuck_in_start_here)
                .where(slack_coc_requested_at: nil)
                .where(birthday: ..User::MINIMUM_AGE.years.ago.to_date)
                .where(slack_joined_at: ..WAIT.ago)
    since ? scope.where(slack_joined_at: since..) : scope
  end

end
