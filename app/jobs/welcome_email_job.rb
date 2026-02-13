# frozen_string_literal: true

class WelcomeEmailJob < ApplicationJob
  queue_as :default

  def perform(user)
    # Send welcome email after email confirmation
    Rails.logger.info "Sending welcome email to #{user.email}"

    # TODO: Uncomment when mailer is set up
    # UserMailer.welcome_email(user).deliver_now
  end
end
