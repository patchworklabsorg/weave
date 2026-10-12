# frozen_string_literal: true

# Asks a member for their birthday when Weave doesn't have it, as the first
# step of the /slack onboarding page. Weave needs it to check the member's age
# (see User#minor? and User#under_minimum_age?). A member sets it only once.
class BirthdaysController < ApplicationController
  layout "sessions"

  def create
    if current_user.birthday.present?
      redirect_to slack_onboarding_path
      return
    end

    current_user.birthday = parse_date(params[:birthday])
    current_user.valid?
    if current_user.birthday.nil? || current_user.errors.include?(:birthday)
      current_user.birthday = nil
      @step = current_user.slack_onboarding_step
      @form_errors = { birthday: t("birthday.invalid") }
      render "slack_onboarding/show", status: :unprocessable_content
      return
    end

    # Only the birthday is checked: an unrelated field that fails validation
    # on an old account must not block this step.
    current_user.save!(validate: false)
    after_birthday
  end

  private

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end

  def after_birthday
    if current_user.under_minimum_age?
      AdminMailer.under_minimum_age(current_user).deliver_later
      RevokeLostAppAccessJob.perform_later(user_id: current_user.id)
      redirect_to slack_onboarding_path
      return
    end

    # The Slack invite waits for a birthday (see InviteToSlackJob).
    InviteToSlackJob.perform_later(current_user.id) unless current_user.guardian_consent_missing? || current_user.in_slack_workspace?

    # Sent here from an app's sign-in (see Oauth::AuthorizationsController).
    return_to = session.delete(:birthday_return_to).to_s
    if return_to.start_with?("/oauth/authorize")
      redirect_to return_to
    else
      redirect_to slack_onboarding_path, notice: t("birthday.saved")
    end
  end

end
