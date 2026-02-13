# frozen_string_literal: true

class TestMailer < ApplicationMailer
  def test_email(recipient_email)
    @timestamp = Time.current
    @environment = Rails.env

    mail(
      to: recipient_email,
      subject: env_subject("Test Email - SMTP Configuration")
    )
  end
end
