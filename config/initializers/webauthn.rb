# frozen_string_literal: true

# The one WebAuthn relying party for Weave. Passkey sign-in (see User::Passkey
# and PasskeyAuthentication) and the break-glass hardware keys (see
# KeyCustody.relying_party) both use it, so both features have the same RP id,
# origin and algorithms.
#
# The relying party id is the host the credential belongs to. A credential
# made on weave.patchworklabs.org works only there, and one made on staging
# works only on staging, so each deployment reads its own host from Weave.host.
#
# Development uses http://localhost on PORT (foreman's bin/dev sets
# PORT=5000), or port 3000 when PORT is unset. Set WEBAUTHN_ORIGIN (for
# example http://localhost:3100) to override it. The host must be localhost:
# browsers treat it as a secure origin, and WebAuthn does not accept an IP
# address such as 127.0.0.1 as an RP id. Test always uses
# http://localhost:3000.
WebAuthn.configure do |config|
  origin = Weave.webauthn_origin

  config.rp_id = URI(origin).host
  config.allowed_origins = [origin]
  config.rp_name = Weave.staging? ? "Weave (staging)" : "Weave"

  # ES256 is what almost every authenticator uses. RS256 is for Windows Hello
  # on older machines. EdDSA is for some security keys (a YubiKey 5 offers it
  # first when the server lists it).
  config.algorithms = %w(ES256 EdDSA RS256)
end
