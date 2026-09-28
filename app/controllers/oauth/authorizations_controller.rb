# frozen_string_literal: true

module Oauth
  # Doorkeeper's authorization endpoint, with one addition: the consent forms
  # are allowed to submit their way to the client's registered redirect URI.
  #
  # Weave's global CSP sets `form-action 'self'` (see
  # config/initializers/content_security_policy.rb), and Chrome and Safari apply
  # form-action to *every hop* of a form submission's redirect chain, not just to
  # the form's own action. Granting consent POSTs same-origin to /oauth/authorize,
  # which answers `302` to the client's redirect_uri — a cross-origin hop the
  # browser then refuses to make, and refuses silently. Server-side nothing looks
  # wrong: Rails logs the POST, logs "Redirected to https://client/...", and
  # returns 302. The client simply never receives the code, so no token exchange
  # ever follows, and the user sees an Authorize button that does nothing at all.
  #
  # Firefox does not enforce form-action across redirects, so this breaks for
  # only some people, which is worse than breaking for everyone.
  #
  # The allowance is derived from what the application registered, never from the
  # redirect_uri parameter, so a crafted request cannot widen the policy by
  # asking to be sent somewhere new. Doorkeeper has already checked the parameter
  # against this same list before any consent screen renders.
  class AuthorizationsController < Doorkeeper::AuthorizationsController
    include OauthClientRedirectOrigins

    content_security_policy do |policy|
      policy.form_action(:self, *redirect_origins_for(pre_auth.client&.application))
    end

  end
end
