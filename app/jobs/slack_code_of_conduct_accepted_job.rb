# frozen_string_literal: true

# Runs when someone accepts the code of conduct: with the button in their Slack
# DM, with the Slack form, or on the /slack onboarding page. Records the
# acceptance, promotes a single-channel guest to full workspace member, and
# marks them a member in Weave once Slack confirms the promotion.
#
# A full member who joined before the code-of-conduct flow is already a member,
# so only the acceptance is recorded for them.
#
# message is the Slack DM that asked for the acceptance, as { channel:, ts: }.
# When it is given, the DM is replaced with a thank-you so its button can't be
# used again.
class SlackCodeOfConductAcceptedJob < ApplicationJob
  queue_as :default

  def perform(slack_user_id, message: nil)
    return if slack_user_id.blank?

    user = User.find_by(slack_id: slack_user_id)
    user&.update_columns(slack_coc_accepted_at: Time.current) if user&.slack_coc_accepted_at.nil?

    service = SlackService.new
    return unless service.configured?

    already_member = user&.slack_member?
    replace_message(service, message, already_member:) if message.present?
    return if already_member

    result = service.promote_to_member(slack_user_id)
    if result[:ok]
      user&.update_columns(slack_membership: "member", updated_at: Time.current)
      Rails.logger.info "Promoted #{slack_user_id} to full member after CoC acceptance"
    else
      Rails.logger.error "Failed to promote #{slack_user_id} after CoC acceptance: #{result[:error]}"
    end
  rescue SlackService::ConfigurationError => e
    Rails.logger.error "Slack not configured for promotion: #{e.message}"
  end

  private

  def replace_message(service, message, already_member:)
    service.mark_code_of_conduct_accepted(channel: message[:channel], ts: message[:ts], already_member:)
  rescue => e
    Rails.logger.error "Failed to update CoC DM #{message.inspect}: #{e.message}"
  end

end
