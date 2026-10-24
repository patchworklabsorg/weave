# frozen_string_literal: true

# Enrolling and revoking a key holder's hardware keys (see KeyCustody).
#
# A key holder enrolls hardware_keys_per_holder keys (a primary and a
# backup) from their own session, on their own computer. The key must
# support the WebAuthn PRF extension (hmac-secret on a YubiKey), because PRF
# opens the holder's share.
#
# The seal key: the browser turns the PRF output for the key's seal_salt into
# an X25519 key pair (HKDF-SHA256, "weave key custody seal key v1") and sends
# only the public key. The ceremony seals the holder's share to it, so no
# hardware key ever has to touch another person's computer.
#
# The seal salt is made before the create step (seal_salt_for, from the
# single-use registration challenge) and goes in the registration options.
# Enrollment then takes one or two touches:
# - One touch: the browser asks for PRF at creation
#   (extensions.prf.eval.first = seal salt). A key that evaluates PRF at
#   creation (hmac-secret-mc, for example YubiKey 5.8) gives the output at
#   once. The browser derives the seal key pair and sends the seal public key
#   with the registration. The registration challenge, bound to the user and
#   signed into the attestation, is the proof that the key was present.
# - Two touches: a key that only has hmac-secret (for example YubiKey 5.4),
#   or a browser without PRF at creation, gives no output. enroll! stores the
#   key without a seal key, and register_seal_key! takes an assertion of the
#   key with PRF on the same seal salt.
module KeyCustody
  module Enrollment
    ALGORITHMS = [-8, -7, -257].freeze # EdDSA, ES256, RS256

    module_function

    def can_enroll?(user) = KeyCustody.holder?(user) && user.identity_hardware_keys.active.count < VerificationSettings.hardware_keys_per_holder

    # The roles the user can still enroll.
    def open_roles(user) = IdentityHardwareKey::ROLES - user.identity_hardware_keys.active.pluck(:role)

    # The options for navigator.credentials.create, as JSON for the browser.
    def creation_options(user)
      raise Refused, "Only a key holder with fewer than #{VerificationSettings.hardware_keys_per_holder} keys can enroll one." unless can_enroll?(user)

      challenge = Assertions.issue!(user:, purpose: "enroll", subject: user.public_id)
      seal_salt = seal_salt_for(challenge.challenge)
      rp = KeyCustody.relying_party
      {
        challenge: challenge.challenge,
        rp: { id: rp.id, name: rp.name },
        user: { id: Assertions.encode(user.public_id), name: user.email.to_s, displayName: user.full_name.to_s },
        pubKeyCredParams: ALGORITHMS.map { |alg| { type: "public-key", alg: } },
        timeout: 120_000,
        attestation: "none",
        authenticatorSelection: { authenticatorAttachment: "cross-platform", residentKey: "discouraged",
                                  userVerification: Assertions.user_verification
},
        excludeCredentials: user.identity_hardware_keys.map { |key| { type: "public-key", id: key.external_id } },
        # PRF at creation, on the seal salt: one touch where the key can.
        extensions: { prf: { eval: { first: seal_salt } } },
        seal_salt:
      }
    end

    # The seal salt of a key enrolled with this registration challenge, as
    # Base64url. The challenge is 32 random bytes from Weave and works once,
    # so each key gets its own salt. The same value serves both paths: PRF at
    # creation and the later seal key assertion.
    def seal_salt_for(challenge)
      Base64.urlsafe_encode64(OpenSSL::Digest.digest("SHA256", "weave key custody seal salt v1|#{challenge}"), padding: false)
    end

    # Registers a hardware key. credential is the JSON of the new
    # credential, with clientExtensionResults.prf.enabled true.
    # seal_public_key (Base64) is the seal public key that the browser
    # derived from the PRF output at creation, or nil when the key gave none
    # (then register_seal_key! follows).
    def enroll!(user, credential:, role:, nickname: nil, seal_public_key: nil)
      raise Refused, "Only a key holder with fewer than #{VerificationSettings.hardware_keys_per_holder} keys can enroll one." unless can_enroll?(user)
      raise Refused, "Choose the role of the key: #{open_roles(user).join(' or ')}." unless open_roles(user).include?(role)
      raise Refused, "No hardware key answer was sent." unless credential.is_a?(Hash)

      seal_bytes = decode_seal_public_key(seal_public_key) if seal_public_key.present?

      webauthn = WebAuthn::Credential.from_create(credential, relying_party: KeyCustody.relying_party)
      challenge = KeyCustodyChallenge.usable.find_by(user:, purpose: "enroll", subject: user.public_id,
                                                     challenge: Assertions.encode(webauthn.response.client_data.challenge))
      raise Refused, "The challenge is unknown, expired or already used. Start again." if challenge.nil?

      webauthn.verify(challenge.challenge, user_verification: VerificationSettings.require_user_verification?)
      unless credential.dig("clientExtensionResults", "prf", "enabled") == true
        raise Refused, "This key does not support the PRF extension (hmac-secret), so it can't hold a share."
      end
      raise Refused, "The challenge is already used. Start again." unless challenge.consume!

      key = nil
      event = nil
      IdentityHardwareKey.transaction do
        key = user.identity_hardware_keys.create!(external_id: webauthn.id, public_key: webauthn.public_key,
                                                  sign_count: webauthn.sign_count, role:, nickname: nickname.to_s.strip.presence,
                                                  seal_salt: seal_salt_for(challenge.challenge),
                                                  seal_public_key: seal_bytes && Base64.strict_encode64(seal_bytes))
        event = KeyCustodyEvent.record!(:hardware_key_enrolled, actor: user, subject: user, hardware_key_id: key.public_id, role:,
                                                                one_touch: seal_bytes.present?)
        if seal_bytes
          KeyCustodyEvent.record!(:seal_key_registered, actor: user, subject: user, hardware_key_id: key.public_id,
                                                        at_enrollment: true)
        end
      end
      # A new key of a key holder is security news: a stolen session could
      # enroll a key it controls. The board is told.
      KeyCustody.notify_board(event)
      key
    rescue WebAuthn::Error, JSON::ParserError, ArgumentError, CBOR::UnpackError => e
      raise Refused, "The hardware key answer is not valid (#{e.class.name.demodulize})."
    rescue ActiveRecord::RecordInvalid => e
      raise Refused, e.record.errors.full_messages.to_sentence
    end

    # The options to register the seal key of a new key: a challenge for
    # this key, and PRF on its seal_salt.
    def seal_key_options(user, key)
      raise Refused, "Only the holder can set up their own key." unless key.user_id == user.id && key.active?
      raise Refused, "This key already has its seal key." if key.seal_public_key.present?

      challenge = Assertions.issue!(user:, purpose: "seal_key", subject: key.public_id)
      Assertions.request_options(challenge, keys: [key], prf: { key.external_id => { first: key.seal_salt } })
                .merge(hardware_key_id: key.public_id)
    end

    # Stores the seal public key of a key, sent with a fresh assertion of
    # that key for its seal_key challenge. Weave can't check that the public
    # key comes from the PRF output: only the holder's browser has it. The
    # assertion proves the key was present when the browser made it.
    def register_seal_key!(user, key, credential:, seal_public_key:)
      raise Refused, "Only the holder can set up their own key." unless key.user_id == user.id && key.active?
      raise Refused, "This key already has its seal key." if key.seal_public_key.present?

      bytes = decode_seal_public_key(seal_public_key)
      Assertions.verify!(credential, user:, purpose: "seal_key", subject: key.public_id, keys: [key])
      key.update!(seal_public_key: Base64.strict_encode64(bytes))
      KeyCustodyEvent.record!(:seal_key_registered, actor: user, subject: user, hardware_key_id: key.public_id)
      key
    end

    def decode_seal_public_key(value)
      bytes = Base64.strict_decode64(value.to_s)
      raise Refused, "The seal public key must be #{Crypto::KEY_BYTES} bytes." unless bytes.bytesize == Crypto::KEY_BYTES

      bytes
    rescue ArgumentError
      raise Refused, "The seal public key is not valid Base64."
    end

    # Revokes a lost or broken key: the holder, or an owner. The key's
    # wrapped shares are deleted, so the key can't open a share again. The
    # board is told. A holder with no key left that opens their share of the
    # current key set makes that set compromised: it must be rotated.
    def revoke!(key, by:, reason:)
      raise Refused, "Only the holder or an owner can revoke a hardware key." unless by.present? && (by.id == key.user_id || by.owner?)
      raise Refused, "Write why the key is revoked." if reason.blank?
      raise Refused, "This key is already revoked." unless key.active?

      event = nil
      IdentityHardwareKey.transaction do
        key.lock!
        key.update!(revoked_at: Time.current, revoked_by: by, revoked_reason: reason.to_s.strip)
        key.wrapped_shares.delete_all
        event = KeyCustodyEvent.record!(:hardware_key_revoked, actor: by, subject: key.user, hardware_key_id: key.public_id,
                                                               role: key.role, reason: key.revoked_reason)
      end
      KeyCustody.notify_board(event)
      check_holder_can_open!(key.user, by)
      key
    end

    # A holder with no hardware key that opens their share of the current
    # key set: the set is compromised and must be rotated. The same for a
    # pending set: it can't be activated any more, because nobody can open
    # one of its shares. A new ceremony replaces it.
    def check_holder_can_open!(user, by)
      [KeyCustody.current_key_set, KeyCustody.pending_key_set].compact.each do |key_set|
        share = key_set.share_for(user)
        next if share.nil? || Recovery.keys_for(share).any?

        KeyCustody.mark_compromised!(key_set, reason: "holder_lost_all_keys", actor: by, subject: user)
      end
    end
  end
end
