# frozen_string_literal: true

# After "Document OK", opens a Slack group DM with the member, the
# pre-reviewer and the Weave bot, so they can agree a time for the call. The
# bot stays in the DM, so no team member talks to a member (who can be under
# 18) in a private one-to-one DM. The member also gets the usual email, so a
# member who is not in Slack loses nothing.
#
# It runs once per attempt: the scheduling_dm_opened event marks it done.
class OpenCallSchedulingDmJob < ApplicationJob
  queue_as :default

  retry_on Slack::Web::Api::Errors::TooManyRequestsError, attempts: 10,
                                                          wait: ->(executions) { [executions * 30, 300].min }
  retry_on Slack::Web::Api::Errors::ServerError, wait: :polynomially_longer, attempts: 5

  def perform(verification_id)
    verification = Verification.find_by(id: verification_id)
    return unless verification&.awaiting_call?
    return if verification.events.exists?(kind: "scheduling_dm_opened")

    member = verification.user
    reviewer = verification.pre_reviewer
    return if member&.slack_id.blank? || reviewer&.slack_id.blank?

    service = SlackService.new
    return unless service.configured?

    text = I18n.t("verification.slack.scheduling_dm", member: "<@#{member.slack_id}>", reviewer: "<@#{reviewer.slack_id}>")
    channel = service.post_group_dm([member.slack_id, reviewer.slack_id], text)
    VerificationEvent.record!(verification, :scheduling_dm_opened, actor: reviewer, channel:)
    NotifyIdentityTeamJob.perform_later("scheduling_dm_opened", verification, actor: reviewer)
  rescue Slack::Web::Api::Errors::SlackError => e
    # Rate limits and server errors are not SlackErrors, so retry_on gets
    # them. This is a guest the bot can't reach, a missing scope or a deactivated account.
    # The member still has the email, so log it and stop.
    level = SlackService.setup_error?(e) ? :error : :warn
    Rails.logger.public_send(level, "OpenCallSchedulingDmJob: no group DM for verification #{verification_id}: #{e.message}")
  end

end
