# frozen_string_literal: true

# Tells the identity team's private Slack channel that work waits for them,
# with a link to the page in the identity area. The message names the
# attempt by its public id only: no member name, no document details, so
# Slack keeps no personal data from the check.
#
#   NotifyIdentityTeamJob.perform_later("verification_submitted", verification)
#   NotifyIdentityTeamJob.perform_later("residency_submitted", residency_check)
#   NotifyIdentityTeamJob.perform_later("escalated", verification)
#
# Does nothing when Slack or the channel is not set up.
class NotifyIdentityTeamJob < ApplicationJob
  queue_as :default

  KINDS = %w[verification_submitted residency_submitted escalated].freeze

  retry_on Slack::Web::Api::Errors::TooManyRequestsError, attempts: 10,
                                                          wait: ->(executions) { [executions * 30, 300].min }
  retry_on Slack::Web::Api::Errors::ServerError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveJob::DeserializationError

  def perform(kind, record)
    raise ArgumentError, "unknown kind #{kind}" unless KINDS.include?(kind)

    service = SlackService.new
    return unless service.configured? && service.identity_channel.present?

    service.post_to_identity_channel(I18n.t("verification.slack.team.#{kind}", link: "<#{url_for_record(record)}|#{record.public_id}>"))
  rescue Slack::Web::Api::Errors::SlackError => e
    # For example, the bot is not in the channel. The queue pages still list
    # the work, so log it and stop.
    Rails.logger.warn "NotifyIdentityTeamJob: #{kind} not posted: #{e.message}"
  end

  private

  def url_for_record(record)
    helpers = Rails.application.routes.url_helpers
    path = record.is_a?(ResidencyCheck) ? helpers.identity_residency_check_path(record) : helpers.identity_verification_path(record)
    "#{Weave.url}#{path}"
  end

end
