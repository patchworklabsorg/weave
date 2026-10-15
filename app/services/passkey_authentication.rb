# frozen_string_literal: true

# The two WebAuthn ceremonies behind passkeys: adding a passkey to a signed-in
# account, and signing in with one.
#
# Each ceremony has two steps. The server makes a challenge (the *_options
# methods), the browser has the authenticator sign it, and the server checks
# the result (register! and authenticate!). The caller keeps the challenge
# between the two steps (see PasskeyChallenges) and must use it only once.
#
# Both ceremonies require user verification (a PIN, fingerprint or face). That
# is what lets a passkey replace the email link on its own: the device is one
# factor and the verification is a second.
class PasskeyAuthentication
  # Why a ceremony failed. The controllers turn the reason into a message.
  class Failure < StandardError
    attr_reader :reason

    def initialize(reason)
      @reason = reason
      super("Passkey #{reason}")
    end
  end

  # The credential JSON that the browser sends is at most a few kilobytes.
  # Anything much larger is not a credential.
  MAX_CREDENTIAL_BYTES = 16.kilobytes

  class << self
    # Options for navigator.credentials.create. resident_key "required" makes
    # the passkey discoverable, so sign-in can start without an email address.
    def registration_options(user)
      WebAuthn::Credential.options_for_create(
        user: {
          id: user.ensure_webauthn_id!,
          name: user.email,
          display_name: user.full_name
        },
        exclude: user.passkeys.pluck(:external_id),
        authenticator_selection: {
          resident_key: "required",
          user_verification: "required"
        }
      )
    end

    def register!(user, credential:, challenge:, nickname: nil)
      raise Failure, :expired if challenge.blank?

      webauthn_credential = parse(credential) { |data| WebAuthn::Credential.from_create(data) }

      begin
        webauthn_credential.verify(challenge, user_verification: true)
      rescue WebAuthn::Error => e
        Rails.logger.info "Passkey registration refused for user #{user.id}: #{e.class.name}"
        raise Failure, :invalid
      end

      raise Failure, :duplicate if User::Passkey.exists?(external_id: webauthn_credential.id)

      user.passkeys.create!(
        external_id: webauthn_credential.id,
        public_key: webauthn_credential.public_key,
        sign_count: webauthn_credential.sign_count.to_i,
        nickname: nickname.to_s.first(User::Passkey::NICKNAME_MAX_LENGTH)
      )
    end

    # Options for navigator.credentials.get. The allow list is empty, so the
    # browser offers every passkey it has for this site.
    def sign_in_options
      WebAuthn::Credential.options_for_get(user_verification: "required")
    end

    # Returns the passkey that signed the challenge. Raises Failure when the
    # passkey is unknown, compromised, or does not verify, or when its owner
    # cannot sign in.
    def authenticate!(credential:, challenge:)
      raise Failure, :expired if challenge.blank?

      webauthn_credential = parse(credential) { |data| WebAuthn::Credential.from_get(data) }

      passkey = User::Passkey.includes(:user).find_by(external_id: webauthn_credential.id)
      raise Failure, :unknown if passkey.nil?
      raise Failure, :compromised if passkey.compromised?

      # The user handle the authenticator gives back must belong to the same
      # account as the credential id.
      user_handle = webauthn_credential.user_handle
      raise Failure, :unknown if user_handle.present? && user_handle != passkey.user.webauthn_id

      verify_assertion!(passkey, webauthn_credential, challenge)
      raise Failure, :inactive unless passkey.user.can_authenticate?

      passkey
    end

    private

    def parse(credential)
      data = credential.is_a?(String) ? decode(credential) : credential
      raise Failure, :invalid unless data.is_a?(Hash)

      yield data.deep_stringify_keys
    rescue Failure
      raise
    rescue StandardError => e
      # Bad input fails in many places inside the gem (Base64, CBOR, COSE), and
      # not all of them raise WebAuthn::Error.
      Rails.logger.info "Passkey credential could not be read: #{e.class.name}"
      raise Failure, :invalid
    end

    def decode(credential)
      raise Failure, :invalid if credential.bytesize > MAX_CREDENTIAL_BYTES

      JSON.parse(credential)
    end

    # The row lock makes the sign-count check and update one step, so two
    # requests with the same assertion cannot both pass.
    def verify_assertion!(passkey, webauthn_credential, challenge)
      compromised = false

      User::Passkey.transaction do
        passkey.lock!

        begin
          webauthn_credential.verify(
            challenge,
            public_key: passkey.public_key,
            sign_count: passkey.sign_count,
            user_verification: true
          )
        rescue WebAuthn::SignCountVerificationError
          # The authenticator's counter went back. That can mean someone copied
          # the key, so the passkey stops working until its owner removes it.
          passkey.update!(compromised_at: Time.current)
          compromised = true
          next
        rescue WebAuthn::Error => e
          Rails.logger.info "Passkey sign-in refused for passkey #{passkey.id}: #{e.class.name}"
          raise Failure, :invalid
        end

        passkey.update!(sign_count: webauthn_credential.sign_count.to_i, last_used_at: Time.current)
      end

      return unless compromised

      Rails.logger.warn "Passkey #{passkey.id} of user #{passkey.user_id} marked compromised: sign count went back"
      raise Failure, :compromised
    end

  end
end
