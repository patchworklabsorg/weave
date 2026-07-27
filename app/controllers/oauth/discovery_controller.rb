# frozen_string_literal: true

# OAuth 2.0 Authorization Server Metadata (RFC 8414)
# https://datatracker.ietf.org/doc/html/rfc8414
#
# OpenID Connect discovery is NOT served from here. It is rendered by
# Doorkeeper::OpenidConnect::DiscoveryController (see config/routes.rb), so the
# OIDC document is generated from real configuration.
#
# Everything advertised below is likewise derived from Doorkeeper's actual
# configuration rather than a hardcoded list. Publishing a capability we do not
# have is a correctness bug: clients trust this document.
module Oauth
  class DiscoveryController < ActionController::API
    include Doorkeeper::OpenidConnect::GrantTypesSupportedMixin
    include Doorkeeper::OpenidConnect::TokenEndpointAuthMethodsSupportedMixin

    def oauth_authorization_server
      base_url = "#{request.protocol}#{request.host_with_port}"
      doorkeeper = Doorkeeper.config

      metadata = {
        # Must agree with the `iss` in issued id_tokens and with the OIDC
        # discovery document, so it comes from configuration, not the Host
        # header.
        issuer: Doorkeeper::OpenidConnect.resolve_issuer(request: request),

        authorization_endpoint: "#{base_url}/oauth/authorize",
        token_endpoint: "#{base_url}/oauth/token",
        revocation_endpoint: "#{base_url}/oauth/revoke",
        introspection_endpoint: "#{base_url}/oauth/introspect",
        userinfo_endpoint: "#{base_url}#{oauth_userinfo_path}",
        jwks_uri: "#{base_url}#{oauth_discovery_keys_path}",

        grant_types_supported: grant_types_supported(doorkeeper),
        response_types_supported: doorkeeper.authorization_response_types,

        # The registered scopes, verbatim. This is the whole point: a scope that
        # is advertised but not configured fails with invalid_scope when a
        # client actually asks for it.
        scopes_supported: doorkeeper.scopes.to_a,

        token_endpoint_auth_methods_supported: token_endpoint_auth_methods_supported,
        revocation_endpoint_auth_methods_supported: token_endpoint_auth_methods_supported,
        introspection_endpoint_auth_methods_supported: token_endpoint_auth_methods_supported,

        code_challenge_methods_supported: doorkeeper.pkce_code_challenge_methods_supported,

        service_documentation: "#{base_url}/docs/oauth"
      }

      render json: metadata
    end

  end
end
