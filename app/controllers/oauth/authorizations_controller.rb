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
    content_security_policy do |policy|
      policy.form_action(:self, *client_redirect_origins)
    end

    private

    def client_redirect_origins
      application = pre_auth.client&.application
      return [] if application.blank?

      application.redirect_uri.to_s.split.filter_map { |uri| origin_of(uri) }.uniq
    end

    # Only http(s) origins mean anything to form-action. Native clients register
    # custom schemes and the out-of-band URN, which belong in no CSP — dropping
    # them keeps a malformed or exotic entry from widening or breaking the header.
    def origin_of(uri)
      parsed = URI.parse(uri)
      return nil unless parsed.is_a?(URI::HTTP) && parsed.host.present?

      origin = "#{parsed.scheme}://#{parsed.host}"
      return origin if parsed.port.nil? || parsed.port == parsed.default_port

      "#{origin}:#{parsed.port}"
    rescue URI::InvalidURIError
      nil
    end

  end
end
