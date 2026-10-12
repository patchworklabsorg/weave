# frozen_string_literal: true

# The steps of a parent or guardian's consent for a member under 18, with what
# each one sets off (see GuardianConsent).
#
#   member asks (request) -> guardian gets a link -> guardian consents (grant)
#   -> member can join the Slack and use apps
#
# The guardian can take the consent back from the same link (revoke). The
# member then loses app access, and the admins are told, because the Slack
# account stays as it is until an admin acts.
module GuardianConsentFlow
  Result = Data.define(:consent, :errors) do
    def success? = errors.empty?
  end

  class << self
    # The member gives their guardian's name and email. Returns a Result whose
    # errors are keyed by field, for the form.
    def request(user, guardian_name:, guardian_email:)
      consent = GuardianConsent.issue!(user, guardian_name:, guardian_email:)
      return Result.new(consent:, errors: consent.errors.to_hash.transform_values(&:first)) unless consent.persisted?

      GuardianConsentMailer.request_consent(consent, consent.token).deliver_later
      Result.new(consent:, errors: {})
    end

    # Sends the open request again, with a new link. Returns false inside the
    # cooldown.
    def resend(consent)
      return false unless consent.pending? && consent.resend_allowed?

      consent.reissue!
      GuardianConsentMailer.request_consent(consent, consent.token).deliver_later
      true
    end

    # The guardian consents from the link. token is the raw token from the
    # link: the receipt email repeats it, so the guardian can revoke later.
    def grant(consent, token:, signed_name:, ip:, user_agent:, fingerprint: nil)
      return false unless consent.record_grant!(signed_name:, ip:, user_agent:, fingerprint:)

      flag(consent)

      GuardianConsentMailer.receipt(consent, token).deliver_later
      GuardianConsentMailer.granted(consent).deliver_later
      after_consent(consent.user)
      true
    end

    # An admin records consent given outside Weave.
    def record_offline(user, guardian_name:, guardian_email:, recorded_by:, note:)
      consent = GuardianConsent.record_offline!(user, guardian_name:, guardian_email:, recorded_by:, note:)
      return Result.new(consent:, errors: consent.errors.to_hash.transform_values(&:first)) unless consent.persisted?

      GuardianConsentMailer.granted(consent).deliver_later
      after_consent(user)
      Result.new(consent:, errors: {})
    end

    # by is the admin who revoked it, or nil when the guardian did.
    def revoke(consent, by: nil)
      return false unless consent.record_revoke!(by:)

      GuardianConsentMailer.revoked(consent).deliver_later
      AdminMailer.guardian_consent_revoked(consent).deliver_later if by.nil?
      RevokeLostAppAccessJob.perform_later(user_id: consent.user_id)
      true
    end

    # An admin contacted the guardian and confirmed the consent.
    def review(consent, by:, note:)
      return false unless consent.needs_review?

      consent.record_review!(by:, note:)
      true
    end

    private

    # Flags a consent for the admin review queue. The consent stands: an admin
    # checks it, and revokes it if the guardian is not real.
    def flag(consent)
      flags = GuardianConsentSignals.for(consent)
      return if flags.empty?

      consent.update_columns(flags:) # rubocop:disable Rails/SkipsModelValidations
      AdminMailer.guardian_consent_flagged(consent).deliver_later if consent.suspicious?
    end

    # Consent was the only thing that held back the Slack invite (see
    # InviteToSlackJob). Members already in the workspace need none.
    def after_consent(user)
      InviteToSlackJob.perform_later(user.id) if user.email_verified? && !user.in_slack_workspace?
    end

  end
end
