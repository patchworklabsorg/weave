# frozen_string_literal: true

# Pushes a user's pronouns to their Slack profile after they change in Weave.
# Reads the current value when it runs, so a burst of edits ends with Slack
# holding the last one.
class PushPronounsToSlackJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return if user&.slack_id.blank?

    SlackService.new.update_slack_pronouns(user.slack_id, user.pronouns)
  end

end
