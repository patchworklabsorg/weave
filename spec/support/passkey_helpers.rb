# frozen_string_literal: true

require "webauthn/fake_client"

# A fake browser and authenticator for passkey specs. The origin matches the
# relying party in config/initializers/webauthn.rb for the test environment.
module PasskeyHelpers
  PASSKEY_ORIGIN = "http://localhost:3000"

  def fake_passkey_client
    WebAuthn::FakeClient.new(PASSKEY_ORIGIN)
  end

  # Runs the registration ceremony for user and returns the stored passkey.
  def register_passkey(user, client: fake_passkey_client, nickname: nil)
    options = PasskeyAuthentication.registration_options(user)
    credential = client.create(challenge: options.challenge, user_verified: true)
    PasskeyAuthentication.register!(user, credential: credential.to_json, challenge: options.challenge, nickname: nickname)
  end

  # A signed assertion for challenge, the way the browser sends it.
  def passkey_assertion(client, challenge, user:, **options)
    client.get(
      challenge: challenge,
      user_verified: true,
      user_handle: WebAuthn.configuration.encoder.decode(user.webauthn_id),
      **options
    ).to_json
  end
end

RSpec.configure do |config|
  config.include PasskeyHelpers
end
