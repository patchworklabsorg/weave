# frozen_string_literal: true

class InviteToSlackJob < ApplicationJob
  queue_as :default

  def perform(email)
    # Send Slack invitation
    Rails.logger.info "Sending Slack invitation to #{email}"

    # TODO: Implement Slack API integration
    # SlackService.invite_user(email)
  end
end
