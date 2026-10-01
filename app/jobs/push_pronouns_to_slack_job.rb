# frozen_string_literal: true

# Pushes a user's pronouns to their Slack profile after they change in Weave.
# Reads the current value when it runs, so a burst of edits ends with Slack
# holding the last one. Slack errors and rate limits are retried. Until a push
# succeeds, the Slack sync keeps the Weave value (see User#apply_slack_pronouns!).
class PushPronounsToSlackJob < ApplicationJob
  queue_as :default

  retry_on Slack::Web::Api::Errors::TooManyRequestsError, attempts: 10,
                                                          wait: ->(executions) { [executions * 30, 300].min }
  retry_on Slack::Web::Api::Errors::SlackError, Slack::Web::Api::Errors::ServerError,
           wait: :polynomially_longer, attempts: 5

  def perform(user_id)
    user = User.find_by(id: user_id)
    return if user&.slack_id.blank?

    pronouns = user.pronouns
    return unless SlackService.new.update_slack_pronouns(user.slack_id, pronouns)

    user.record_pronouns_pushed_to_slack!(pronouns)
  end

end
