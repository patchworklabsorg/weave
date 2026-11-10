# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  include Rails.application.routes.url_helpers
  has_history
  utm_params
  default from: -> { Weave.mail_from }, reply_to: -> { Weave.mail_address }
  layout "mailer"

  def env_subject(base_subject)
    Rails.env.production? ? base_subject : "[#{Rails.env.upcase}] #{base_subject}"
  end

  # Renders the email with times in the recipient's zone (User#time_zone).
  # A recipient who is not a user, or more than one recipient, gets UTC.
  def mail(headers = {}, &)
    Time.use_zone(recipient_time_zone(headers[:to])) { super }
  end

  private

  def recipient_time_zone(to)
    recipients = Array(to).compact_blank
    user = User.find_by(email: recipients.first.to_s.downcase) if recipients.one?
    user&.time_zone || ActiveSupport::TimeZone["UTC"]
  end


end
