# frozen_string_literal: true

# Adds a new full Slack member to the member channels (see
# SlackService#member_channels). SlackCodeOfConductAcceptedJob enqueues it
# after a promotion.
#
# A channel that fails (rate limit, expired admin session) is tried again
# later on its own, up to ATTEMPTS times, with a longer wait each time.
class JoinSlackChannelsJob < ApplicationJob
  queue_as :default

  ATTEMPTS = 5

  # channels nil means every member channel. attempt counts the runs so far.
  def perform(slack_user_id, channels = nil, attempt: 1)
    service = SlackService.new
    return unless service.configured?

    failed = channels ? service.add_to_channels(slack_user_id, channels) : service.add_to_channels(slack_user_id)
    return if failed.empty?

    if attempt < ATTEMPTS
      self.class.set(wait: (attempt**2).minutes).perform_later(slack_user_id, failed.keys, attempt: attempt + 1)
    else
      Rails.logger.error "Gave up adding #{slack_user_id} to Slack channels: #{failed.inspect}"
    end
  end

end
