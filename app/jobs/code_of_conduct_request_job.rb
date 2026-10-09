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
class CodeOfConductRequestJob < ApplicationJob
  queue_as :default

  # deadline is the date after which members who have not accepted move to
  # guest access. nil leaves the deadline out of the message.
  def perform(user_id, deadline: nil, reminder: false)
    user = User.find_by(id: user_id)
    return unless user&.can_authenticate?
    return if user.slack_coc_accepted_at.present?
    return if user.slack_coc_requested_at.present? && !reminder

    send_slack_dm(user, deadline) if user.slack_id.present?
    UserMailer.code_of_conduct_request(user, deadline: deadline).deliver_later
    user.update_columns(slack_coc_requested_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  # The opening of the message, as plain-text paragraphs. Shared by the Slack
  # DM and the email.
  def self.paragraphs(user, deadline: nil)
    t = ->(key, **args) { I18n.t("code_of_conduct_request.#{key}", **args) }
    [
      # Capitalized like User#full_name: many Slack-imported names are lowercase.
      t.call(:greeting, first_name: user.name_missing? ? "there" : user.first_name.gsub(/\b\p{L}/, &:upcase)),
      *t.call(:update).split(/\n{2,}/),
      (t.call(:name_missing) if user.name_missing?),
      (t.call(:deadline, deadline: deadline.strftime("%B %-d, %Y")) if deadline)
    ].compact
  end

  private

  # A Slack failure must not stop the email.
  def send_slack_dm(user, deadline)
    service = SlackService.new
    return unless service.configured?

    intro = [*self.class.paragraphs(user, deadline:), I18n.t("code_of_conduct_request.slack_action")].join("\n\n")
    service.post_code_of_conduct(user.slack_id, intro: intro, collect_name: user.name_missing?)
  rescue => e
    Rails.logger.error "Failed to DM the CoC request to #{user.slack_id}: #{e.message}"
  end

end
