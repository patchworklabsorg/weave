# frozen_string_literal: true

# Keeps a WebAuthn challenge in the session between the two steps of a passkey
# ceremony (see PasskeyAuthentication).
#
# A challenge is good for one check only: take_passkey_challenge removes it
# before the credential is read, so a failed or repeated request cannot use it
# again. It also expires after CHALLENGE_TTL, so a sign-in prompt left open does
# not stay valid.
module PasskeyChallenges
  extend ActiveSupport::Concern

  CHALLENGE_TTL = 5.minutes
  PURPOSES = %i[registration sign_in].freeze

  private

  def store_passkey_challenge(purpose, challenge)
    session[passkey_challenge_key(purpose)] = {
      "value"      => challenge,
      "expires_at" => CHALLENGE_TTL.from_now.to_i
    }
  end

  # The challenge, or nil when there is none or it expired.
  def take_passkey_challenge(purpose)
    stored = session.delete(passkey_challenge_key(purpose))
    return nil unless stored.is_a?(Hash)
    return nil if stored["expires_at"].to_i < Time.current.to_i

    stored["value"].presence
  end

  def passkey_challenge_key(purpose)
    raise ArgumentError, "unknown passkey challenge purpose: #{purpose}" unless PURPOSES.include?(purpose)

    :"passkey_#{purpose}_challenge"
  end
end
