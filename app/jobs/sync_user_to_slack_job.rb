# frozen_string_literal: true

# Syncs IDP user to Slack (profile updates only, no invitations)
# Triggered when user confirms their email
class SyncUserToSlackJob < ApplicationJob
  queue_as :default
  retry_on SlackService::ApiError, wait: :exponentially_longer, attempts: 3

  def perform(user_id)
    user = User.find(user_id)
    slack_service = SlackService.new

    # Check if user exists in Slack
    slack_user = slack_service.find_user_by_email(user.email)

    if slack_user
      # User exists in Slack, update their slack_id
      if user.slack_id.blank?
        user.update!(
          slack_id: slack_user["id"],
          slack_joined_at: Time.zone.at(slack_user["updated"].to_i)
        )
        Rails.logger.info "User #{user.email} found in Slack, updated slack_id"
      end

      # Sync PWL ID to Slack profile if user has p_id
      if user.p_id.present?
        slack_service.send(:update_slack_profile_field, slack_user["id"], user.p_id)
        Rails.logger.info "Synced PWL ID for #{user.email} to Slack profile"
      end
    else
      # User not in Slack workspace yet
      Rails.logger.info "User #{user.email} not in Slack workspace, skipping sync"
    end
  rescue SlackService::ConfigurationError => e
    Rails.logger.error "Slack not configured: #{e.message}"
    # Don't retry if Slack is not configured
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "User not found: #{e.message}"
    # Don't retry if user doesn't exist
  end

end
