# frozen_string_literal: true

class SlackWebhookEventJob < ApplicationJob
  queue_as :default

  def perform(event_data)
    event_type = event_data.dig('event', 'type')
    event_id = event_data['event_id']

    Rails.logger.info "[SlackWebhookEventJob] Processing event #{event_id}: #{event_type}"

    case event_type
    when 'team_join'
      # New user joined Slack workspace
      slack_user_data = event_data['event']['user']
      SlackWebhookService.process_team_join(slack_user_data)
      Rails.logger.info "[SlackWebhookEventJob] Processed team_join for user #{slack_user_data['id']}"

    when 'user_change'
      # User profile updated in Slack
      slack_user_data = event_data['event']['user']
      SlackWebhookService.process_user_change(slack_user_data)
      Rails.logger.info "[SlackWebhookEventJob] Processed user_change for user #{slack_user_data['id']}"

    else
      Rails.logger.warn "[SlackWebhookEventJob] Unhandled event type: #{event_type}"
    end

    # Mark as processed in cache
    cache_key = "slack_event_processed:#{event_id}"
    Rails.cache.write(cache_key, true, expires_in: 24.hours)
  rescue => e
    Rails.logger.error "[SlackWebhookEventJob] Error processing event #{event_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise # Re-raise to allow job retry mechanism
  end
end
