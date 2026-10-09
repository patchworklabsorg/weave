# frozen_string_literal: true

# Moves a full member who joined before the code-of-conduct flow, and did not
# accept it by the deadline, back to a single-channel guest in the
# code-of-conduct channel. They then go through the same flow as a new member:
# a DM and an email ask them to accept, and accepting promotes them again (see
# SlackCodeOfConductAcceptedJob).
#
# Slack workspace admins and owners can't be demoted. They get their own
# request instead: a DM whose button opens the form with the box to check,
# and an email. Their apps already need the acceptance (see AppAccess).
#
# Enqueued by `bin/rails slack:coc:demote`. Skips anyone who accepted in the
# meantime.
class DemoteForCodeOfConductJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user&.slack_member? && user.slack_id.present?
    return if user.slack_coc_accepted_at.present?

    service = SlackService.new
    return unless service.configured?

    if service.workspace_admin?(user.slack_id)
      Rails.logger.info "Not demoting Slack admin #{user.slack_id} for CoC; sending the admin request"
      notify(service, user, reason: :admin, form: true)
      return
    end

    result = service.demote_to_guest(user.slack_id)
    unless result[:ok]
      Rails.logger.error "Failed to demote #{user.slack_id} for CoC: #{result[:error]}"
      return
    end

    user.update_columns(slack_membership: "pending", updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    notify(service, user, reason: :demoted, form: user.name_missing?)
  end

  private

  # A Slack failure must not stop the email.
  def notify(service, user, reason:, form:)
    begin
      service.post_code_of_conduct(
        user.slack_id,
        title: CodeOfConductRequestJob.slack_title(reason),
        paragraphs: CodeOfConductRequestJob.paragraphs(user, reason:),
        form: form
      )
    rescue => e
      Rails.logger.error "Failed to DM the CoC (#{reason}) to #{user.slack_id}: #{e.message}"
    end
    UserMailer.code_of_conduct_request(user, reason:).deliver_later
    user.update_columns(slack_coc_requested_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

end
