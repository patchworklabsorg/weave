# frozen_string_literal: true

# Tells the identity team's private Slack channel what happens in a member's
# identity checks, with a link to the page in the identity area.
#
# All notices about one member go into one thread (IdentitySlackThread): the
# first notice is the parent message, the next ones are replies. A notice
# that asks the team for new work (NEEDS_ACTION) is also sent to the channel
# (reply_broadcast), so it is not lost in an old thread.
#
# The messages name the member by Weave ID and the attempt by its public id
# only: no member name, no document details and no note to the member, so
# Slack keeps no personal data from the checks. Team members are named.
#
#   NotifyIdentityTeamJob.perform_later("verification_submitted", verification)
#   NotifyIdentityTeamJob.perform_later("call_scheduled", verification, actor: by, at: at)
#
# Does nothing when Slack or the channel is not set up.
class NotifyIdentityTeamJob < ApplicationJob
  queue_as :default

  NEEDS_ACTION = %w[verification_submitted residency_submitted escalated].freeze
  KINDS = (NEEDS_ACTION + %w[
    pre_review_started pre_review_taken_over document_approved document_rejected scheduling_dm_opened
    call_scheduled decided escalation_resolved
    residency_pre_review_started residency_rejected residency_decided
  ]).freeze

  retry_on Slack::Web::Api::Errors::TooManyRequestsError, attempts: 10,
                                                          wait: ->(executions) { [executions * 30, 300].min }
  retry_on Slack::Web::Api::Errors::ServerError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveJob::DeserializationError

  def perform(kind, record, actor: nil, **details)
    raise ArgumentError, "unknown kind #{kind}" unless KINDS.include?(kind)

    service = SlackService.new
    return unless service.configured? && service.identity_channel.present?

    text = I18n.t("verification.slack.team.#{kind}", link: link(record), actor: actor&.full_name || "Someone",
                                                     **details.transform_values { |value| format_value(value) })
    post(service, record.user, text, broadcast: NEEDS_ACTION.include?(kind))
  rescue Slack::Web::Api::Errors::SlackError => e
    # For example, the bot is not in the channel. The queue pages still list
    # the work, so log it and stop.
    level = SlackService.setup_error?(e) ? :error : :warn
    Rails.logger.public_send(level, "NotifyIdentityTeamJob: #{kind} not posted: #{e.message}")
  end

  private

  # The first notice about a member starts the thread. The row lock keeps two
  # jobs from starting two threads for the same member.
  def post(service, user, text, broadcast:)
    return service.post_to_identity_channel(text) if user.nil?

    thread = IdentitySlackThread.for(user, service.identity_channel)
    started = thread.with_lock do
      next false if thread.ts.present?

      parent = I18n.t("verification.slack.team.thread_parent", weave_id: user.p_id, text:)
      thread.update!(ts: service.post_to_identity_channel(parent))
      true
    end
    service.post_to_identity_channel(text, thread_ts: thread.ts, broadcast:) unless started
  end

  def link(record)
    helpers = Rails.application.routes.url_helpers
    path = record.is_a?(ResidencyCheck) ? helpers.identity_residency_check_path(record) : helpers.identity_verification_path(record)
    "<#{Weave.url}#{path}|#{record.public_id}>"
  end

  # A time shows in each reader's own time zone (Slack date formatting).
  def format_value(value)
    return value.to_s unless value.acts_like?(:time)

    "<!date^#{value.to_i}^{date_short_pretty} at {time}|#{value.utc.strftime('%Y-%m-%d %H:%M UTC')}>"
  end

end
