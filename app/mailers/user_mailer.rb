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

  # Sent to the primary address when Slack adds a new address to the account,
  # so the user finds out if someone else changed their Slack profile.
  def slack_email_address_added(email_address)
    @email_address = email_address
    @user = email_address.user
    @profile_url = edit_profile_url

    mail(
      to: @user.email,
      subject: env_subject("A new email address was added to your account")
    )
  end

  # Asks a member who joined the Slack before the code-of-conduct flow to
  # accept it (see CodeOfConductRequestJob). Signing in sends them to /slack,
  # which shows the accept step.
  def code_of_conduct_request(user, deadline: nil)
    @user = user
    @paragraphs = CodeOfConductRequestJob.paragraphs(user, deadline:)
    @login_url = login_url
    @code_of_conduct_url = SlackService.code_of_conduct_url

    mail(
      to: @user.email,
      subject: env_subject(I18n.t("code_of_conduct_request.subject"))
    )
  end

end
