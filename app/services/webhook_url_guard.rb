# frozen_string_literal: true

require "resolv"

# Stops a webhook URL from reaching Weave's own network (SSRF).
#
# An admin types the URL, but the host name can point anywhere, and its DNS
# can change after the webhook is saved. So the check runs at each delivery,
# after DNS resolution: every address of the host must be public. The caller
# then connects to the returned address, so a second DNS answer can't swap in
# a private one (DNS rebinding).
#
# In production (staging too) the URL must use https. In development, http
# and loopback addresses are allowed, so a receiver can run on localhost.
module WebhookUrlGuard
  class Blocked < StandardError; end

  # Ranges that IPAddr#private?, #loopback? and #link_local? do not cover.
  BLOCKED_RANGES = %w[
    0.0.0.0/8
    100.64.0.0/10
    192.0.0.0/24
    192.0.2.0/24
    198.18.0.0/15
    198.51.100.0/24
    203.0.113.0/24
    224.0.0.0/4
    240.0.0.0/4
    255.255.255.255/32
    ::/128
    64:ff9b::/96
    2001:db8::/32
    ff00::/8
  ].map { |range| IPAddr.new(range) }.freeze

  class << self
    def https_only? = Rails.env.production?

    # Returns [uri, address] for a URL that may be called, or raises Blocked.
    def check!(url)
      uri = parse(url)
      addresses = resolve(uri.hostname)
      raise Blocked, "#{uri.hostname} does not resolve" if addresses.empty?

      blocked = addresses.reject { |address| allowed?(address) }
      raise Blocked, "#{uri.hostname} resolves to a blocked address (#{blocked.join(', ')})" if blocked.any?

      [uri, addresses.first.to_s]
    end

    def allowed?(address)
      address = address.ipv4_mapped? ? address.native : address
      return Rails.env.development? if address.loopback?
      return false if address.private? || address.link_local?

      BLOCKED_RANGES.none? { |range| range.include?(address) }
    end

    private

    def parse(url)
      uri = URI.parse(url.to_s)
      raise Blocked, "the URL must use https" if https_only? && uri.scheme != "https"
      raise Blocked, "the URL must use http or https" unless %w[http https].include?(uri.scheme)
      raise Blocked, "the URL has no host" if uri.hostname.blank?
      raise Blocked, "the URL must not hold a user name or password" if uri.userinfo.present?

      uri
    rescue URI::InvalidURIError => e
      raise Blocked, "the URL is not valid (#{e.message})"
    end

    def resolve(host)
      return [IPAddr.new(host)] if ip_literal?(host)

      Resolv.getaddresses(host).filter_map do |address|
        IPAddr.new(address)
      rescue IPAddr::InvalidAddressError
        nil
      end
    end

    def ip_literal?(host)
      IPAddr.new(host)
      true
    rescue IPAddr::InvalidAddressError
      false
    end

  end
end
