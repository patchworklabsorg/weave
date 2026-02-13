# frozen_string_literal: true

class NotifyOpsOnNewUserJob < ApplicationJob
  queue_as :default

  def perform(user)
    # Notify ops team about new user signup
    Rails.logger.info "Notifying ops about new user: #{user.email} (#{user.p_id})"

    # TODO: Implement ops notification (Slack webhook, email, etc.)
    # SlackService.notify_channel('#ops', "New user signed up: #{user.email}")
  end
end
