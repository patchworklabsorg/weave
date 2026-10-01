# frozen_string_literal: true

# Runs when a single-channel guest accepts the code of conduct, either with the
# button in their Slack DM or on the /slack onboarding page. Records the
# acceptance, promotes them from guest to full workspace member, and marks
# them a member in Weave once Slack confirms the promotion.
class SlackCodeOfConductAcceptedJob < ApplicationJob
  queue_as :default

  def perform(slack_user_id)
    return if slack_user_id.blank?

    user = User.find_by(slack_id: slack_user_id)
    user&.update_columns(slack_coc_accepted_at: Time.current) if user&.slack_coc_accepted_at.nil?

    service = SlackService.new
    return unless service.configured?

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

end
