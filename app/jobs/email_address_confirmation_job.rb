# frozen_string_literal: true

class EmailAddressConfirmationJob < ApplicationJob
  queue_as :default

  def perform(email_address)
    return if email_address.confirmed? || email_address.confirmation_token.blank?

    UserMailer.email_address_confirmation(email_address).deliver_now
  end

end
