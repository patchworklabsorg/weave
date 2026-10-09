# frozen_string_literal: true

# Sets the name on a user's Slack profile after they give it on the
# code-of-conduct form (see CodeOfConductAcceptance). With a nickname, only
# the Slack display name is set, so the preferred name stays out of Slack.
# Without one, the Slack first and last name are set to the preferred name.
# Slack errors and rate limits are retried.
class PushSlackNameJob < ApplicationJob
  queue_as :default

  retry_on Slack::Web::Api::Errors::TooManyRequestsError, attempts: 10,
                                                          wait: ->(executions) { [executions * 30, 300].min }
  retry_on Slack::Web::Api::Errors::SlackError, Slack::Web::Api::Errors::ServerError,
           wait: :polynomially_longer, attempts: 5

  def perform(user_id, nickname: nil)
    user = User.find_by(id: user_id)
    return if user&.slack_id.blank?

    profile = if nickname.present?
                { display_name: nickname }
              else
                { first_name: user.first_name, last_name: user.last_name }
              end
    SlackService.new.update_slack_profile_name(user.slack_id, **profile)
  end

end
