# frozen_string_literal: true

class AdminMailer < ApplicationMailer
  default to: "jasper@patchworklabs.org"

  def email_throttle_warning(count, date)
    @count = count
    @date = date
    @limit = Interceptors::EmailThrottleInterceptor::DAILY_LIMIT
    @remaining = @limit - @count

    mail(
      subject: "[IDP Alert] Approaching daily email limit (#{@remaining} remaining)"
    )
  end

  # A guardian took back consent for a member under 18 (see
  # GuardianConsentFlow). Weave removes app access, but the Slack account
  # stays as it is, so an admin decides what happens there.
  def guardian_consent_revoked(consent)
    @user = consent.user
    @admin_user_url = admin_user_url(@user)

    mail(subject: "[IDP Alert] Guardian consent revoked for #{@user.full_name}")
  end

end
