# frozen_string_literal: true

# Preview all emails at http://localhost:3000/rails/mailers/guardian_consent_mailer
# Each preview uses an unsaved consent, so nothing is written.
class GuardianConsentMailerPreview < ActionMailer::Preview
  def request_consent = GuardianConsentMailer.request_consent(consent, "preview-token")

  def receipt = GuardianConsentMailer.receipt(consent, "preview-token")

  def granted = GuardianConsentMailer.granted(consent)

  def revoked = GuardianConsentMailer.revoked(consent)

  private

  def consent
    GuardianConsent.new(user: User.first, guardian_name: "Grace Hopper", guardian_email: "grace@example.org")
  end

end
