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

  # A member said they are under User::MINIMUM_AGE (see BirthdaysController).
  # Weave removes app access, but the account and any Slack account stay, so
  # an admin decides what happens to them.
  def under_minimum_age(user)
    @user = user
    @admin_user_url = admin_user_url(@user)

    mail(subject: "[IDP Alert] Member under #{User::MINIMUM_AGE}: #{@user.full_name}")
  end

  # A guardian consent with a sign that the guardian may not be real (see
  # GuardianConsentSignals). It waits in the admin review queue.
  def guardian_consent_flagged(consent)
    @user = consent.user
    @consent = consent
    @queue_url = admin_guardian_consents_url

    mail(subject: "[IDP Alert] Check the guardian consent for #{@user.full_name}")
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
