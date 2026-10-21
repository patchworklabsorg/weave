# frozen_string_literal: true

# Asks a full Slack member who joined before the code-of-conduct flow to
# accept it (User.code_of_conduct_pending). Sends the request two ways,
# because many members don't check Slack often:
#
# - a Slack DM with a button that accepts (or opens a form that also asks for
#   a missing name), and
# - an email with a link to sign in to Weave and accept on /slack.
#
# The text is in config/locales/code_of_conduct_request.en.yml. Enqueued by
# `bin/rails slack:coc:request`. Idempotent: a member who has accepted is
# skipped, and so is one who was already asked, unless reminder is true.
#
# reason picks the text (see .paragraphs). NudgeStuckSlackGuestsJob sends
# :onboarding to new guests who never accepted.
#
# With refresh: true, the job sends nothing new. It rewrites the DMs that were
# already sent (users.slack_coc_messages) with the current text and links.
class CodeOfConductRequestJob < ApplicationJob
  queue_as :default

  # deadline is the date after which members who have not accepted move to
  # guest access. nil leaves the deadline out of the message.
  def perform(user_id, deadline: nil, reminder: false, refresh: false, reason: :update)
    reason = reason.to_sym
    user = User.find_by(id: user_id)
    return unless user&.can_authenticate?
    return if user.slack_coc_accepted_at.present?
    return refresh_slack_dms(user, deadline, reason) if refresh
    return if user.slack_coc_requested_at.present? && !reminder

    send_slack_dm(user, deadline, reason) if user.slack_id.present?
    UserMailer.code_of_conduct_request(user, deadline: deadline, reason: reason).deliver_later
    user.update_columns(slack_coc_requested_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  # The opening of the message, as plain-text paragraphs. Shared by the Slack
  # DM and the email.
  #
  # reason is :update for the first request, :demoted for a member who did not
  # accept by the deadline and is now a guest, :admin for a Slack admin who
  # can't be demoted (see DemoteForCodeOfConductJob), or :onboarding for a new
  # guest who never accepted (see NudgeStuckSlackGuestsJob).
  def self.paragraphs(user, deadline: nil, reason: :update)
    t = ->(key, **args) { I18n.t("code_of_conduct_request.#{key}", **args) }
    [
      # Capitalized like User#full_name: many Slack-imported names are lowercase.
      t.call(:greeting, first_name: user.name_missing? ? "there" : user.first_name.gsub(/\b\p{L}/, &:upcase)),
      *t.call(reason).split(/\n{2,}/),
      (t.call(:name_missing) if user.name_missing?),
      (t.call(:deadline, deadline: deadline.strftime("%B %-d, %Y")) if deadline && reason == :update)
    ].compact
  end

  # The header of the Slack DM for a reason (see .paragraphs).
  def self.slack_title(reason) = I18n.t("code_of_conduct_request.slack_titles.#{reason}")

  private

  # A Slack failure must not stop the email.
  def send_slack_dm(user, deadline, reason)
    service = SlackService.new
    return unless service.configured?

    service.post_code_of_conduct(user.slack_id, **slack_message(user, deadline, reason))
  rescue => e
    Rails.logger.error "Failed to DM the CoC request to #{user.slack_id}: #{e.message}"
  end

  # One failed update must not stop the others.
  def refresh_slack_dms(user, deadline, reason)
    service = SlackService.new
    return unless service.configured?

    user.slack_coc_messages.each do |message|
      service.update_code_of_conduct(channel: message["channel"], ts: message["ts"], slack_user_id: user.slack_id,
                                     **slack_message(user, deadline, reason))
    rescue => e
      Rails.logger.error "Failed to refresh the CoC DM #{message["ts"]} for #{user.slack_id}: #{e.message}"
    end
  end

  def slack_message(user, deadline, reason)
    { title: self.class.slack_title(reason), paragraphs: self.class.paragraphs(user, deadline:, reason:), form: user.name_missing? }
  end

end
