# frozen_string_literal: true

class UserMailer < ApplicationMailer
  def welcome_email(user)
    @user = user

    mail(
      to: @user.email,
      subject: env_subject("Welcome to Patchwork Labs")
    )
  end

end
