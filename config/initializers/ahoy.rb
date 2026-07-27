# frozen_string_literal: true

class Ahoy::Store < Ahoy::DatabaseStore
end

# set to true for JavaScript tracking
Ahoy.api = false

# set to true for geocoding (and add the geocoder gem to your Gemfile)
# we recommend configuring local geocoding as well
# see https://github.com/ankane/ahoy#geocoding
Ahoy.geocode = true

# Ahoy's default `user_method` tries `current_user` and then falls back to
# Doorkeeper's `current_resource_owner`. On Doorkeeper's own controllers that
# fallback is not a passive read: `current_resource_owner` invokes the
# `resource_owner_authenticator` block in config/initializers/doorkeeper.rb,
# which redirects to /oauth/login when nobody is signed in.
#
# Ahoy runs as a `before_action` on every controller, so that redirect fired
# before the endpoint's own code did, and every unauthenticated OAuth endpoint
# answered 302 to a login page:
#
#   POST /oauth/token                       -> 302 /oauth/login
#   GET  /.well-known/openid-configuration  -> 302 /oauth/login
#   GET  /oauth/discovery/keys              -> 302 /oauth/login
#
# All three must be reachable without a session: discovery and JWKS by OIDC
# Discovery 1.0, and the token endpoint by RFC 6749 section 3.2, which
# authenticates the *client*, not a resource owner. No relying party could
# finish a flow, or even bootstrap one.
#
# So only `current_user` is consulted. Attributing an analytics visit is not
# worth calling an authenticator that has side effects. Doorkeeper's controllers
# do not define `current_user`, so their visits are recorded anonymously.
Ahoy.user_method = lambda do |controller|
  controller.send(:current_user) if controller.respond_to?(:current_user, true)
end
