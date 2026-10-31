# frozen_string_literal: true

# Email for a parent or guardian's consent (see GuardianConsentFlow). The
# guardian gets the request and a receipt. The member hears when consent is
# given or ends.
class GuardianConsentMailer < ApplicationMailer
  # token is the raw link token. It exists only in this email and in the job
  # arguments, as with MagicLinkMailer.
  def request_consent(consent, token)
    @consent = consent
    @user = consent.user
    @consent_url = guardian_consent_url(token:)

    mail(to: consent.guardian_email, subject: env_subject(t("guardian_consent.mailer.request_subject", first_name: @user.first_name)))
  end

  def receipt(consent, token)
    @consent = consent
    @user = consent.user
    @consent_url = guardian_consent_url(token:)

    mail(to: consent.guardian_email, subject: env_subject(t("guardian_consent.mailer.receipt_subject", first_name: @user.first_name)))
  end

  def granted(consent)
    @user = consent.user
    @account_url = profile_url

    mail(to: @user.email, subject: env_subject(t("guardian_consent.mailer.granted_subject")))
  end

  def revoked(consent)
    @user = consent.user

    mail(to: @user.email, subject: env_subject(t("guardian_consent.mailer.revoked_subject")))
  end

end
