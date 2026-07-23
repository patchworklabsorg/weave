# frozen_string_literal: true

class WelcomeEmailJob < ApplicationJob
  queue_as :default

  def perform(user)
    return unless user

    Rails.logger.info "Sending welcome email to #{user.email}"
    UserMailer.welcome_email(user).deliver_now
  end

end
