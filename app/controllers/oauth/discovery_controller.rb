# frozen_string_literal: true

# OAuth 2.0 Authorization Server Metadata (RFC 8514)
# https://datatracker.ietf.org/doc/html/rfc8414
module Oauth
  class DiscoveryController < ActionController::API
    def oauth_authorization_server
      base_url = "#{request.protocol}#{request.host_with_port}"
      
      metadata = {
        issuer: base_url,
        authorization_endpoint: "#{base_url}/oauth/authorize",
        token_endpoint: "#{base_url}/oauth/token",
        revocation_endpoint: "#{base_url}/oauth/revoke",
        introspection_endpoint: "#{base_url}/oauth/introspect",
        userinfo_endpoint: "#{base_url}/oauth/userinfo",
        
        # Supported grant types
        grant_types_supported: [
          "authorization_code",
          "client_credentials",
          "refresh_token"
        ],
        
        # Supported response types
        response_types_supported: [
          "code",
          "token"
        ],
        
        # Supported scopes
        scopes_supported: [
          "profile",
          "email",
          "admin"
        ],
        
        # Token endpoint authentication methods
        token_endpoint_auth_methods_supported: [
          "client_secret_basic",
          "client_secret_post"
        ],
        
        # Additional capabilities
        revocation_endpoint_auth_methods_supported: [
          "client_secret_basic",
          "client_secret_post"
        ],
        
        introspection_endpoint_auth_methods_supported: [
          "client_secret_basic",
          "client_secret_post"
        ],
        
        # PKCE support
        code_challenge_methods_supported: [
          "S256",
          "plain"
        ],
        
        # Service documentation
        service_documentation: "#{base_url}/docs/oauth"
      }
      
      render json: metadata
    end
    
    # OpenID Connect Discovery (optional but useful)
    def openid_configuration
      base_url = "#{request.protocol}#{request.host_with_port}"
      
      metadata = {
        issuer: base_url,
        authorization_endpoint: "#{base_url}/oauth/authorize",
        token_endpoint: "#{base_url}/oauth/token",
        userinfo_endpoint: "#{base_url}/oauth/userinfo",
        revocation_endpoint: "#{base_url}/oauth/revoke",
        introspection_endpoint: "#{base_url}/oauth/introspect",
        
        # OpenID Connect specific
        subject_types_supported: ["public"],
        id_token_signing_alg_values_supported: ["RS256"],
        
        # Supported scopes
        scopes_supported: [
          "openid",
          "profile",
          "email",
          "admin"
        ],
        
        # Supported response types
        response_types_supported: [
          "code",
          "token"
        ],
        
        # Supported grant types
        grant_types_supported: [
          "authorization_code",
          "client_credentials",
          "refresh_token"
        ],
        
        # Token endpoint authentication methods
        token_endpoint_auth_methods_supported: [
          "client_secret_basic",
          "client_secret_post"
        ],
        
        # Claims supported
        claims_supported: [
          "sub",
          "name",
          "given_name",
          "family_name",
          "preferred_username",
          "email",
          "email_verified",
          "admin"
        ],
        
        # PKCE support
        code_challenge_methods_supported: [
          "S256",
          "plain"
        ]
      }
      
      render json: metadata
    end
  end
end
