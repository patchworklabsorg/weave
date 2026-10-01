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
# Encrypted credentials are the only source. The key is NEVER committed and has
# no environment variable override: an id_token signed by an unexpected key is
# indistinguishable to a client from an id_token signed by an attacker's key, so
# there should be exactly one place it can come from.
#
# Add one per environment with:
#
#   openssl genrsa 2048
#   bin/rails credentials:edit --environment production
#
#   openid_connect:
#     signing_key: |
#       -----BEGIN PRIVATE KEY-----
#       ...
#
# Test is the sole exception, mirroring the throwaway key in lockbox.rb: CI has
# no credential keys at all, so the suite generates an ephemeral one in memory.
module OidcSigningKey
  # RSA modulus size for the generated test key. Real keys are generated out of
  # band by whoever adds them to credentials.
  KEY_SIZE = 2048

  MISSING_KEY_MESSAGE = <<~MSG.squish
    No OIDC signing key configured. Add a PEM-encoded RSA private key to
    encrypted credentials under openid_connect.signing_key — see
    config/initializers/doorkeeper_openid_connect.rb for the exact steps.
  MSG

  class << self
    # Memoized so we pay the PEM parse (and, in test, the keygen) once per
    # process rather than on every id_token we sign.
    def fetch!
      @fetch ||= configured_key || test_key || raise(MISSING_KEY_MESSAGE)
    end

    private

    def configured_key
      Rails.application.credentials.dig(:openid_connect, :signing_key).presence
    end

    # Generated per process and never written to disk, so no key material of any
    # kind exists in the repository or on a CI runner. The suite runs in a
    # single process, so JWKS and the signing path agree on one key.
    def test_key
      return unless Rails.env.test?

      OpenSSL::PKey::RSA.generate(KEY_SIZE).to_pem
    end

  end
end

Doorkeeper::OpenidConnect.configure do
  # The issuer is the stable identity of this provider. It is baked into every
  # id_token as `iss` and clients pin on it, so it must not be derived from the
  # (attacker-controllable) Host header.
  #
  # Production follows APP_HOST (lib/weave.rb) so staging issues id_tokens for
  # its own host. Test uses the Rack::Test default host so the issuer and the
  # request-derived endpoint URLs in the discovery document agree.
  issuer do
    ENV["OIDC_ISSUER"].presence ||
      case Rails.env
      when "production" then Weave.url
      when "test"       then "http://www.example.com"
      else                   "http://localhost:3000"
      end
  end

  # Callable so a missing key raises on first use rather than aborting boot,
  # which would break `zeitwerk:check`, asset precompilation and anything else
  # that only needs the app to load.
  signing_key -> { OidcSigningKey.fetch! }

  signing_algorithm :rs256

  subject_types_supported [:public]

  # `protocol` is used to build the absolute endpoint URLs in the discovery
  # document. Local environments are served over plain HTTP.
  protocol { Rails.env.local? ? :http : :https }

  resource_owner_from_access_token do |access_token|
    User.find_by(id: access_token.resource_owner_id)
  end

  # `sub` is the Patchwork Labs ID (format: PWL\d[0-9A-F]{9}, SPWL on staging). This matches the
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

    # Not a standard OIDC claim. Omitted when unset.
    normal_claim :pronouns, scope: :profile, response: [:id_token, :user_info] do |user|
      user.pronouns
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

    # Full membership of the Patchwork Labs Slack: in the workspace as a
    # regular member (not a guest) with the code of conduct accepted. A user
    # can sign in while this is false; each client decides what to allow.
    normal_claim :slack_member, scope: :slack, response: [:id_token, :user_info] do |user|
      user.slack_member?
    end

    # The member's Slack user ID (e.g. U0123ABCD). Omitted before they join,
    # because the gem leaves out nil claims.
    # Present for guests too, so check slack_member before inviting it to
    # channels.
    normal_claim :slack_id, scope: :slack, response: [:id_token, :user_info] do |user|
      user.slack_id
    end
  end
end
