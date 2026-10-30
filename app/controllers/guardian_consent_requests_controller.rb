# frozen_string_literal: true

# A member under 18 asks a parent or guardian for consent (see
# GuardianConsentFlow). Only apps that require it need the consent (see
# AppAccess): the Slack does not.
class GuardianConsentRequestsController < ApplicationController
  layout "sessions"

  before_action :require_consent_missing

  def show; end

  def create
    result = GuardianConsentFlow.request(
      current_user,
      guardian_name: params[:guardian_name].to_s,
      guardian_email: params[:guardian_email].to_s
    )

    if result.success?
      redirect_to guardian_consent_request_path, notice: t("guardian_consent.form.sent", email: result.consent.guardian_email)
    else
      @form_errors = result.errors
      render :show, status: :unprocessable_content
    end
  end

  def resend
    consent = current_user.current_guardian_consent
    if consent&.pending? && GuardianConsentFlow.resend(consent)
      redirect_to guardian_consent_request_path, notice: t("guardian_consent.form.resent")
    else
      redirect_to guardian_consent_request_path, alert: t("guardian_consent.form.resend_wait")
    end
  end

  private

  def require_consent_missing
    redirect_to profile_path unless current_user.email_verified? && current_user.guardian_consent_missing?
  end

end
