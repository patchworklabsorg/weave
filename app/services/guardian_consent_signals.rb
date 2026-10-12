# frozen_string_literal: true

# Signs that a guardian consent may not come from a real parent or guardian,
# worked out when the guardian consents (see GuardianConsentFlow.grant).
#
# An email link proves only that someone reads that inbox, so no sign here
# proves anything. A flag puts the consent in the admin review queue
# (Admin::GuardianConsentsController), where an admin contacts the guardian.
# A shared home IP is normal for a real parent, so the IP is not a sign.
module GuardianConsentSignals
  # A random share of consents with no other flag is also checked, so members
  # know that any consent can be checked.
  SPOT_CHECK_RATE = 0.1
  QUICK_GRANT = 5.minutes

  FLAGS = {
    "same_device" => "The guardian consented from a browser the member signed in with.",
    "quick_grant" => "The guardian consented within #{QUICK_GRANT.inspect} of the request.",
    "member_name" => "The guardian's name is the member's name.",
    "spot_check"  => "Chosen at random for a spot check."
  }.freeze

  class << self
    def for(consent, random: Random)
      flags = []
      flags << "same_device" if same_device?(consent)
      flags << "quick_grant" if consent.sent_at && consent.granted_at && consent.granted_at - consent.sent_at < QUICK_GRANT
      flags << "member_name" if member_name?(consent)
      flags << "spot_check" if flags.empty? && random.rand < SPOT_CHECK_RATE
      flags
    end

    def describe(flag) = FLAGS.fetch(flag, flag)

    private

    def same_device?(consent)
      consent.granted_fingerprint.present? &&
        consent.user.user_sessions.exists?(fingerprint: consent.granted_fingerprint)
    end

    def member_name?(consent)
      member_names = [consent.user.full_name, consent.user.legal_full_name].map { |name| normalize(name) }
      [consent.guardian_name, consent.signed_name].any? { |name| member_names.include?(normalize(name)) }
    end

    def normalize(name) = name.to_s.downcase.gsub(/[^\p{L}]/, "")

  end
end
