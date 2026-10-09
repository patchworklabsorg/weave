# frozen_string_literal: true

# Moves a full member who joined before the code-of-conduct flow, and did not
# accept it by the deadline, back to a single-channel guest in the
# code-of-conduct channel. They then go through the same flow as a new member:
# a DM and an email ask them to accept, and accepting promotes them again (see
# SlackCodeOfConductAcceptedJob).
#
# Enqueued by `bin/rails slack:coc:demote`. Skips anyone who accepted in the
# meantime, and Slack workspace admins and owners.
class DemoteForCodeOfConductJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user&.slack_member? && user.slack_id.present?
    return if user.slack_coc_accepted_at.present?

    service = SlackService.new
    return unless service.configured?

    if service.workspace_admin?(user.slack_id)
      Rails.logger.info "Not demoting Slack admin #{user.slack_id} for CoC"
      return
    end

    result = service.demote_to_guest(user.slack_id)
    unless result[:ok]
      Rails.logger.error "Failed to demote #{user.slack_id} for CoC: #{result[:error]}"
      return
    end

    user.update_columns(slack_membership: "pending", updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    notify(service, user)
  end

  private

  # A Slack failure must not stop the email.
  def notify(service, user)
    begin
      intro = [*CodeOfConductRequestJob.paragraphs(user, demoted: true), I18n.t("code_of_conduct_request.slack_action")].join("\n\n")
      service.post_code_of_conduct(user.slack_id, intro: intro, collect_name: user.name_missing?)
    rescue => e
      Rails.logger.error "Failed to DM the CoC to demoted member #{user.slack_id}: #{e.message}"
    end
    UserMailer.code_of_conduct_request(user, demoted: true).deliver_later
  end

end
