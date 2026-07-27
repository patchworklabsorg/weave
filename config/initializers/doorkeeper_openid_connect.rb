# frozen_string_literal: true

# OpenID Connect provider configuration, layered on top of Doorkeeper.
#
# This is the single source of truth for:
#   * the claims we expose (both in the id_token and at /oauth/userinfo), and
#   * the metadata published at /.well-known/openid-configuration.
#
# Do not hand-maintain a parallel copy of either — the discovery document is
# rendered from this configuration plus Doorkeeper's own scope list.

# Resolves the RSA private key used to sign id_tokens.
#
# The key is NEVER committed. Follows the same precedence as the other secret
# bearing initializers in this repo (see resend.rb / encoded_ids.rb):
# environment variable first, then encrypted credentials.
#
# In development and test we fall back to a locally generated key so the app
# and the suite boot without production credentials, mirroring the throwaway
# test key in lockbox.rb. Those fallbacks are unreachable in any other
# environment: production raises instead, loudly, on first use.
module OidcSigningKey
  # Development keeps its key on disk under tmp/ (gitignored) so that restarts
  # and multiple Puma workers agree on one key — otherwise the JWKS endpoint
  # would advertise a public key that does not match the signing worker.
  DEVELOPMENT_KEY_PATH = Rails.root.join("tmp/oidc_signing_key.pem")

  # RSA modulus size for locally generated development/test keys. Production
  # keys are generated out of band (see the OIDC section of the README).
  KEY_SIZE = 2048

  MISSING_KEY_MESSAGE = <<~MSG.squish
    No OIDC signing key configured. Set the OIDC_SIGNING_KEY environment
    variable to a PEM-encoded RSA private key, or store one in encrypted
    credentials under openid_connect.signing_key.
  MSG

  class << self
    # Memoized so we pay the PEM parse (and, locally, the keygen) once per
    # process rather than on every id_token we sign.
    def fetch!
      @fetch ||= configured_key || local_key || raise(MISSING_KEY_MESSAGE)
    end

    private

    def configured_key
      ENV["OIDC_SIGNING_KEY"].presence ||
        Rails.application.credentials.dig(:openid_connect, :signing_key).presence
    end

    def local_key
      return unless Rails.env.local?

      Rails.env.test? ? generate_key : development_key
    end

    # Test runs in a single process and gets a fresh ephemeral key, so no key
    # material is ever written to disk by the suite.
    def generate_key
      OpenSSL::PKey::RSA.generate(KEY_SIZE).to_pem
    end

    def development_key
      return DEVELOPMENT_KEY_PATH.read if DEVELOPMENT_KEY_PATH.exist?

      pem = generate_key
      DEVELOPMENT_KEY_PATH.dirname.mkpath
      # Write via a unique temp file + atomic rename so two workers racing on
      # first boot cannot observe a half-written PEM.
      tmp = DEVELOPMENT_KEY_PATH.sub_ext(".#{Process.pid}.tmp")
      tmp.write(pem)
      tmp.chmod(0o600)
      tmp.rename(DEVELOPMENT_KEY_PATH.to_s)
      pem
    rescue Errno::ENOENT
      # Lost the rename race against another worker; use whatever landed.
      DEVELOPMENT_KEY_PATH.read
    end

  end
end

Doorkeeper::OpenidConnect.configure do
  # The issuer is the stable identity of this provider. It is baked into every
  # id_token as `iss` and clients pin on it, so it must not be derived from the
  # (attacker-controllable) Host header.
  #
  # Test uses the Rack::Test default host so the issuer and the request-derived
  # endpoint URLs in the discovery document agree.
  issuer do
    ENV["OIDC_ISSUER"].presence ||
      case Rails.env
      when "production" then "https://weave.patchworklabs.org"
      when "test"       then "http://www.example.com"
      else                   "http://localhost:3000"
      end
  end

  # Callable so a missing production key raises on first use rather than
  # aborting boot (which would break asset precompilation during deploys).
  signing_key -> { OidcSigningKey.fetch! }

  signing_algorithm :rs256

  subject_types_supported [:public]

  # `protocol` is used to build the absolute endpoint URLs in the discovery
  # document. Local environments are served over plain HTTP.
  protocol { Rails.env.local? ? :http : :https }

  resource_owner_from_access_token do |access_token|
    User.find_by(id: access_token.resource_owner_id)
  end

  # `sub` is the Patchwork Labs ID (format: PWL\d[0-9a-f]{9}). This matches the
  # `sub` the hand-rolled userinfo endpoint has always returned, and clients are
  # expected to allowlist on it, so it MUST NOT change to the primary key.
  subject { |user, _application| user.p_id }

  # Best-available "when did this user actually authenticate" signal: the
  # creation time of their most recent live session. Weave has no step-up
  # (re-)authentication yet, so this is login time and nothing more.
  auth_time_from_resource_owner do |resource_owner|
    next nil if resource_owner.nil?

    resource_owner.user_sessions.not_expired.where(signed_out_at: nil).maximum(:created_at)
  end

  # TODO(#87): implement `reauthenticate_resource_owner` once the step-up
  # authentication system lands. It is required to honour `prompt=login` and
  # `max_age`; until then those parameters raise rather than silently issuing an
  # id_token with a stale `auth_time`, which would be worse.
  #
  # reauthenticate_resource_owner do |resource_owner, return_to|
  #   ...
  # end

  # Claims are keyed off the scopes Doorkeeper already knows about. Keep this in
  # sync with `optional_scopes` in doorkeeper.rb — anything listed here is
  # advertised in `claims_supported` on the discovery document.
  claims do
    normal_claim :name, scope: :profile, response: [:id_token, :user_info] do |user|
      user.full_name
    end

    normal_claim :given_name, scope: :profile, response: [:id_token, :user_info] do |user|
      user.first_name
    end

    normal_claim :family_name, scope: :profile, response: [:id_token, :user_info] do |user|
      user.last_name
    end

    normal_claim :preferred_username, scope: :profile, response: [:id_token, :user_info] do |user|
      user.username
    end

    normal_claim :updated_at, scope: :profile, response: [:id_token, :user_info] do |user|
      user.updated_at.to_i
    end

    normal_claim :email, scope: :email, response: [:id_token, :user_info] do |user|
      user.email
    end

    normal_claim :email_verified, scope: :email, response: [:id_token, :user_info] do |user|
      user.email_verified?
    end

    normal_claim :phone_number, scope: :phone, response: [:id_token, :user_info] do |user|
      user.phone_number
    end

    # There is no phone verification flow yet, so this is unconditionally false.
    # Do not make it truthy until one exists — relying parties treat it as proof.
    normal_claim :phone_number_verified, scope: :phone, response: [:id_token, :user_info] do |_user|
      false
    end

    normal_claim :admin, scope: :admin, response: [:id_token, :user_info] do |user|
      user.admin?
    end
  end
end
