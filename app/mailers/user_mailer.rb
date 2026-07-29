# frozen_string_literal: true

class UserMailer < ApplicationMailer
  def welcome_email(user)
    @user = user

    mail(
      to: @user.email,
      subject: env_subject("Welcome to Patchwork Labs")
    )
  end

  def email_address_confirmation(email_address)
    @email_address = email_address
    @user = email_address.user
    @confirmation_url = confirm_email_address_url(token: email_address.confirmation_token)

    mail(
      to: email_address.email,
      subject: env_subject("Confirm your email address")
    )
  end

end
