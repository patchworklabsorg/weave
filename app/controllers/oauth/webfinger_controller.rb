# frozen_string_literal: true

# WebFinger (RFC 7033) as profiled by OpenID Connect Discovery 1.0 §2.
# https://datatracker.ietf.org/doc/html/rfc7033
#
# Answers one question: "for this identifier, which OpenID provider should I
# talk to?" A client that only knows a user's address starts here, learns the
# issuer, and then reads /.well-known/openid-configuration.
#
# Replaces the gem's implementation, which requires `resource` via
# `params.require` (a 500, not a 400), ignores `rel` filtering, and returns
# plain application/json.
#
# DELIBERATELY NOT AN ACCOUNT ORACLE. The spec permits 404 for an identifier the
# provider does not serve, and a naive reading would 404 on "no such user" —
# which turns an unauthenticated endpoint into a way to test email addresses for
# registration, one request at a time. So existence is never consulted: any
# syntactically valid identifier on our own host gets the same issuer response.
# The only 404 is for a host we do not serve, which reveals nothing about who
# has an account here.
module Oauth
  class WebfingerController < ActionController::API
    # The rel that identifies an OIDC issuer link, per OIDC Discovery 1.0 §2.
    ISSUER_RELATION = "http://openid.net/specs/connect/1.0/issuer"

    def show
      return head :bad_request if resource.blank?
      return head :not_found unless our_host?

      # RFC 7033 §5: responses are public and cross-origin by design; a browser
      # client has to be able to read this.
      response.headers["Access-Control-Allow-Origin"] = "*"
      response.headers["Cache-Control"] = "public, max-age=3600"

      render json: { subject: resource, links: links }, content_type: "application/jrd+json"
    end

    private

    def resource
      params[:resource].presence
    end

    # RFC 7033 §4.3: when one or more `rel` values are given, the response
    # carries only the links that match, and an unmatched `rel` still yields a
    # successful response with an empty link set rather than an error.
    def links
      return [issuer_link] if requested_relations.empty?

      requested_relations.include?(ISSUER_RELATION) ? [issuer_link] : []
    end

    # `rel` may repeat (rel=a&rel=b). Rack's nested-query parsing keeps only the
    # last occurrence, so read them off the raw query string instead.
    def requested_relations
      @requested_relations ||= Array(Rack::Utils.parse_query(request.query_string)["rel"]).compact_blank
    end

    def issuer_link
      { rel: ISSUER_RELATION, href: issuer }
    end

    # Configuration, never the Host header: this value must match the `iss` of
    # every id_token we sign.
    def issuer
      @issuer ||= Doorkeeper::OpenidConnect.resolve_issuer(request: request)
    end

    def our_host?
      host = host_from(resource)

      host.present? && host.casecmp?(URI.parse(issuer).host.to_s)
    end

    # Handles the identifier forms OIDC Discovery 1.0 §2.1 lists: acct: URIs,
    # https: URLs, and bare email-style addresses (which RFC 7033 §4.5 treats as
    # acct:). Anything unparseable is simply not ours.
    def host_from(identifier)
      uri = URI.parse(identifier)

      case uri.scheme
      when "acct", "mailto" then uri.opaque.to_s.split("@").last
      when "http", "https"  then uri.host
      when nil              then identifier.split("@").last if identifier.include?("@")
      end
    rescue URI::InvalidURIError
      nil
    end

  end
end
