# frozen_string_literal: true

class SlackSyncJob < ApplicationJob
  queue_as :default

  def perform(direction: "both")
    slack_service = SlackService.new

    unless slack_service.configured?
      Rails.logger.warn "Slack not configured, skipping sync"
      return
    end

    case direction
    when "slack_to_idp"
      sync_slack_to_idp(slack_service)
    when "idp_to_slack"
      sync_idp_to_slack(slack_service)
    when "both"
      sync_slack_to_idp(slack_service)
      sync_idp_to_slack(slack_service)
    else
      raise ArgumentError, "Invalid direction: #{direction}. Must be 'slack_to_idp', 'idp_to_slack', or 'both'"
    end
  end

  private

  def sync_slack_to_idp(slack_service)
    Rails.logger.info "Starting Slack -> IDP sync"
    result = slack_service.sync_slack_users_to_idp
    Rails.logger.info "Completed Slack -> IDP sync: #{result.inspect}"
    result
  end

  def sync_idp_to_slack(slack_service)
    Rails.logger.info "Starting IDP -> Slack sync"
    result = slack_service.sync_idp_users_to_slack
    Rails.logger.info "Completed IDP -> Slack sync: #{result.inspect}"
    result
  end
end
