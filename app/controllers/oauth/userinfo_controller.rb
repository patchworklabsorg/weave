# frozen_string_literal: true

# OpenID Connect UserInfo endpoint.
# https://openid.net/specs/openid-connect-core-1_0.html#UserInfo
#
# The claims themselves are NOT defined here. They come from the `claims` DSL in
# config/initializers/doorkeeper_openid_connect.rb, which is the same source the
# id_token and the discovery document's `claims_supported` are built from — so
# the three can never disagree.
#
# This exists instead of the gem's Doorkeeper::OpenidConnect::UserinfoController
# for exactly one reason: authorization. That controller accepts `openid` and
# nothing else, but Weave has served this endpoint to `profile` tokens since
# before OIDC existed here, so switching to it would 403 every existing client.
# The response body is identical to the gem's.
module Oauth
  class UserinfoController < ActionController::API
    # `doorkeeper_authorize!` is OR, not AND: a token needs one of these, not
    # both. `:profile` is what a bare `doorkeeper_authorize!` used to resolve to
    # (it is Doorkeeper's `default_scopes`), so every token that worked before
    # still works. `:openid` is added on top so a spec-compliant OIDC client
    # that asked for, say, `openid email` and no `profile` is not turned away.
    before_action -> { doorkeeper_authorize!(:openid, :profile) }
    before_action :reject_tokens_that_are_no_longer_usable

    def show
      render json: Doorkeeper::OpenidConnect::UserInfo.new(doorkeeper_token)
    end

    private

    # Locking, suspending or deactivating an account revokes its tokens (see
    # User#revoke_oauth_access!), but that only runs through model callbacks.
    # This keeps a token from outliving the account's ability to sign in even
    # when the change bypassed them, and from outliving the user's access to a
    # restricted app (see AppAccess).
    def reject_tokens_that_are_no_longer_usable
      return if AppAccess.token_usable?(doorkeeper_token)

      response.headers["WWW-Authenticate"] = 'Bearer error="invalid_token", error_description="The token can no longer be used"'
      head :unauthorized
    end

  end
end
