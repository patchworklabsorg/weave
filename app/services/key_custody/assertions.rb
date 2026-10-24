# frozen_string_literal: true

# WebAuthn challenges and assertion checks for key custody (see KeyCustody).
#
# A challenge belongs to one user, one purpose and one subject. The raw
# challenge holds the purpose and the subject in clear, then 32 random bytes:
#
#   "weave:break_glass:brgl_xxxx:" + random bytes
#
# so an assertion signs the id of the one break-glass request it approves.
# Each challenge works once, which stops a replayed assertion. The
# authenticator's sign count must also go up (the webauthn gem checks it).
module KeyCustody
  module Assertions
    module_function

    def issue!(user:, purpose:, subject:)
      raw = "weave:#{purpose}:#{subject}:".b + SecureRandom.random_bytes(32)
      KeyCustodyChallenge.create!(user:, purpose:, subject:, challenge: encode(raw),
                                  expires_at: VerificationSettings.key_custody_challenge_ttl.from_now)
    end

    # The options for navigator.credentials.get, as JSON for the browser.
    # prf maps a hardware key's external id to its PRF salts
    # ({ first: salt, second: salt }), as Base64url.
    def request_options(challenge, keys:, prf: {})
      options = {
        challenge: challenge.challenge,
        rpId: KeyCustody.relying_party.id,
        timeout: 120_000,
        userVerification: user_verification,
        allowCredentials: keys.map { |key| { type: "public-key", id: key.external_id } }
      }
      options[:extensions] = { prf: { evalByCredential: prf } } if prf.any?
      options
    end

    # Checks an assertion. Returns the hardware key that signed it.
    #
    # - user: who holds the challenge (the signed-in user).
    # - keys: the hardware keys that may sign (for example the active keys
    #   of one holder that wrap a share of this key set).
    # - consume: false when several assertions sign one challenge (the
    #   ceremony). The caller then calls consume! once at the end.
    def verify!(credential, user:, purpose:, subject:, keys:, consume: true)
      raise Refused, "No hardware key answer was sent." unless credential.is_a?(Hash) && credential["id"].present?

      webauthn = WebAuthn::Credential.from_get(credential, relying_party: KeyCustody.relying_party)
      key = keys.find { |candidate| candidate.external_id == webauthn.id && candidate.active? }
      raise Refused, "This hardware key is not one that can open this share, or it is revoked." if key.nil?

      challenge = KeyCustodyChallenge.usable.find_by(user:, purpose:, subject:, challenge: Assertions.encode(webauthn.response.client_data.challenge))
      raise Refused, "The challenge is unknown, expired or already used. Start again." if challenge.nil?

      webauthn.verify(challenge.challenge, public_key: key.public_key, sign_count: key.sign_count,
                                           user_verification: VerificationSettings.require_user_verification?)
      raise Refused, "The challenge is already used. Start again." if consume && !challenge.consume!

      key.update!(sign_count: webauthn.sign_count, last_used_at: Time.current)
      [key, challenge]
    rescue WebAuthn::Error, JSON::ParserError, ArgumentError, CBOR::UnpackError => e
      raise Refused, "The hardware key answer is not valid (#{e.class.name.demodulize})."
    end

    def user_verification = VerificationSettings.require_user_verification? ? "required" : "preferred"

    def encode(bytes) = Base64.urlsafe_encode64(bytes, padding: false)

    def decode(value) = Base64.urlsafe_decode64(value.to_s)
  end
end
