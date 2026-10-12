# frozen_string_literal: true

# A member under 18 asks a parent or guardian for consent (see
# GuardianConsentFlow). The form is a step of the /slack onboarding page.
class GuardianConsentRequestsController < ApplicationController
  layout "sessions"

  before_action :require_consent_step

  def create
    result = GuardianConsentFlow.request(
      current_user,
      guardian_name: params[:guardian_name].to_s,
      guardian_email: params[:guardian_email].to_s
    )

    if result.success?
      redirect_to slack_onboarding_path, notice: t("guardian_consent.form.sent", email: result.consent.guardian_email)
    else
      @step = current_user.slack_onboarding_step
      @form_errors = result.errors
      render "slack_onboarding/show", status: :unprocessable_content
    end
  end

  def resend
    consent = current_user.current_guardian_consent
    if consent&.pending? && GuardianConsentFlow.resend(consent)
      redirect_to slack_onboarding_path, notice: t("guardian_consent.form.resent")
    else
      redirect_to slack_onboarding_path, alert: t("guardian_consent.form.resend_wait")
    end
  end

  private

  def require_consent_step
    redirect_to slack_onboarding_path unless current_user.email_verified? && current_user.guardian_consent_missing?
  end

end
