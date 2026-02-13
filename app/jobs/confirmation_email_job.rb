# frozen_string_literal: true

class ConfirmationEmailJob < ApplicationJob
  queue_as :default

  def perform(user)
    # Send confirmation email with token
    # In production, this would use ActionMailer
    # For now, just log it
    Rails.logger.info "Sending confirmation email to #{user.email}"
    Rails.logger.info "Confirmation URL: #{confirmation_url(user.confirmation_token)}"

    # TODO: Uncomment when mailer is set up
    # UserMailer.confirmation_email(user).deliver_now
  end

  private

  def confirmation_url(token)
    # This would use Rails URL helpers in production
    "#{ENV.fetch('APP_URL', 'http://localhost:3000')}/email_confirmation/confirm?token=#{token}"
  end
end
