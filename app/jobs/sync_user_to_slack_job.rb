# frozen_string_literal: true

# Links a Weave user to their Slack account and sends their Weave ID to it
# (profile updates only, no invitations). See SlackService#sync_weave_id.
class SyncUserToSlackJob < ApplicationJob
  queue_as :default
  retry_on SlackService::ApiError, wait: :exponentially_longer, attempts: 3

  def perform(user_id)
    user = User.find(user_id)

    if SlackService.new.sync_weave_id(user)
      Rails.logger.info "Synced the Weave ID for user #{user.id} to Slack account #{user.slack_id}"
    else
      Rails.logger.info "User #{user.id} not in the Slack workspace, skipping sync"
    end
  rescue SlackService::ConfigurationError => e
    Rails.logger.error "Slack not configured: #{e.message}"
    # Don't retry if Slack is not configured
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "User not found: #{e.message}"
    # Don't retry if user doesn't exist
  end

end
