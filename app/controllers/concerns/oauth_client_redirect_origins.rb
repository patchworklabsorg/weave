# frozen_string_literal: true

# The http(s) origins an OAuth client registered as redirect URIs, for widening
# CSP `form-action` on exactly the pages whose form submissions end in a redirect
# to that client.
#
# Chrome and Safari apply form-action to every hop of a form submission's redirect
# chain, so a same-origin form whose response redirects to the client's
# redirect_uri is silently blocked under a plain `form-action 'self'`. The
# allowance comes from what the application registered (never from request
# params), so a crafted request cannot widen the policy.
module OauthClientRedirectOrigins
  extend ActiveSupport::Concern

  private

  def redirect_origins_for(application)
    return [] if application.blank?

    application.redirect_uri.to_s.split.filter_map { |uri| redirect_origin_of(uri) }.uniq
  end

  # Only http(s) origins mean anything to form-action. Native clients register
  # custom schemes and the out-of-band URN, which belong in no CSP — dropping
  # them keeps a malformed or exotic entry from widening or breaking the header.
  def redirect_origin_of(uri)
    parsed = URI.parse(uri)
    return nil unless parsed.is_a?(URI::HTTP) && parsed.host.present?

    origin = "#{parsed.scheme}://#{parsed.host}"
    return origin if parsed.port.nil? || parsed.port == parsed.default_port

    "#{origin}:#{parsed.port}"
  rescue URI::InvalidURIError
    nil
  end
end
