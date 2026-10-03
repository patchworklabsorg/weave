# frozen_string_literal: true

module Oauth
  # Doorkeeper's token endpoints, with one change to introspection: a token
  # whose user can no longer sign in, or may no longer use the app it was
  # issued to (see AppAccess), is reported as `{"active": false}`.
  #
  # Doorkeeper decides `active` from the token row alone (not expired, not
  # revoked). Revocation follows account and access changes through
  # callbacks, so this is the backstop for any change that skipped them.
  # RFC 7662 section 2.2 says an inactive token gets `active: false` and
  # nothing else, so the reason is not given.
  class TokensController < Doorkeeper::TokensController
    def introspect
      introspection = Doorkeeper::OAuth::TokenIntrospection.new(server, token)

      if introspection.authorized? && token&.accessible? && !AppAccess.token_usable?(token)
        render json: { active: false }, status: :ok
      else
        super
      end
    end

  end
end
