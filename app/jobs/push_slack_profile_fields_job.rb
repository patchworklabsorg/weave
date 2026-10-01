# frozen_string_literal: true

# Pushes the Slack profile fields an admin edited in Weave (title, location,
# organization, cost center, manager and so on) to the user's Slack profile.
# Reads the current values when it runs, so a burst of edits ends with Slack
# holding the last ones. Blank values clear the field in Slack. Slack errors
# and rate limits are retried.
#
# The Slack sync treats Slack as the source of truth for these fields, so an
# edit must reach Slack before the next sync, or the sync reverts it.
class PushSlackProfileFieldsJob < ApplicationJob
  queue_as :default

  retry_on Slack::Web::Api::Errors::TooManyRequestsError, attempts: 10,
                                                          wait: ->(executions) { [executions * 30, 300].min }
  retry_on Slack::Web::Api::Errors::SlackError, Slack::Web::Api::Errors::ServerError,
           wait: :polynomially_longer, attempts: 5

  def perform(user_id)
    user = User.find_by(id: user_id)
    return if user&.slack_id.blank?

    SlackService.new.push_profile_fields(user.slack_id, user)
  end

end
