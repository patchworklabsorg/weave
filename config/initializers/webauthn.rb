# frozen_string_literal: true

# Passkey sign-in (see User::Passkey and PasskeyAuthentication).
#
# The relying party id is the host the passkey belongs to. A passkey made on
# weave.patchworklabs.org works only there, and one made on staging works only
# on staging, so each deployment reads its own host from Weave.host. Development
# and test use localhost, which browsers treat as a secure origin.
WebAuthn.configure do |config|
  if Rails.env.production?
    config.rp_id = Weave.host
    config.allowed_origins = [Weave.url]
  else
    config.rp_id = "localhost"
    config.allowed_origins = ["http://localhost:3000"]
  end

  config.rp_name = Weave.staging? ? "Weave (staging)" : "Weave"

  # ES256 is what almost every authenticator uses. RS256 is for Windows Hello
  # on older machines. EdDSA is for some security keys.
  config.algorithms = %w(ES256 EdDSA RS256)
end
