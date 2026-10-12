# frozen_string_literal: true

require "resolv"

# Checks in DNS that an email address's domain can receive mail, so signups
# with addresses like ada@example.com or ada@foo.test are refused.
#
# A domain can receive mail when it has an MX record, or, without one, an A or
# AAAA record (RFC 5321 section 5.1). It can't when it does not exist, has no
# such records, or publishes a "null MX" (RFC 7505), as example.com does.
#
# A DNS timeout or error counts as deliverable: a DNS outage must not stop
# signups. Only production checks (config.x.check_email_deliverability), so
# tests and development can keep their @example.com addresses.
module EmailDeliverability
  TIMEOUT = 2

  module_function

  def enabled?
    Rails.application.config.x.check_email_deliverability == true
  end

  def deliverable?(email)
    _, at, domain = email.to_s.strip.downcase.rpartition("@")
    return true if at.empty? || domain.empty? # format validation reports these

    mx = lookup(domain, Resolv::DNS::Resource::IN::MX)
    return true if mx.nil?
    return mx.none? { |record| record.exchange.to_s.empty? } if mx.any?

    address = lookup(domain, Resolv::DNS::Resource::IN::A)
    address = lookup(domain, Resolv::DNS::Resource::IN::AAAA) if address == []
    address.nil? || address.any?
  end

  # The records of one type, [] when the domain or the records don't exist, or
  # nil when DNS did not answer.
  def lookup(domain, type)
    config = Resolv::DNS::Config.default_config_hash.merge(raise_timeout_errors: true)
    Resolv::DNS.open(config) do |dns|
      dns.timeouts = TIMEOUT
      records = []
      # The trailing dot keeps the resolver from trying search domains.
      dns.fetch_resource(Resolv::DNS::Name.create("#{domain}."), type) do |reply, _reply_name|
        reply.each_answer { |_name, _ttl, data| records << data if data.is_a?(type) }
      end
      records
    end
  rescue Resolv::ResolvError, ArgumentError, SystemCallError => e
    Rails.logger.warn("EmailDeliverability: no DNS answer for #{domain} (#{e.class}), allowing it")
    nil
  end

end
