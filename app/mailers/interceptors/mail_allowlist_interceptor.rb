# frozen_string_literal: true

module Interceptors
  # Keeps a non-production deployment from mailing real people. Staging sends
  # through the same provider as production, so MAIL_ALLOWLIST (see
  # Weave.mail_allowlist) names who may receive mail: "@domain" entries match a
  # whole domain, anything else an exact address. Recipients not on the list are
  # removed from to/cc/bcc; when none remain the message is not delivered.
  # Unset, it changes nothing.
  #
  # On staging it also prefixes subjects with "[staging] " so an allowed
  # recipient can tell the two deployments apart.
  class MailAllowlistInterceptor
    SUBJECT_PREFIX = "[staging] "

    def self.delivering_email(message)
      filter_recipients(message, Weave.mail_allowlist)
      prefix_subject(message) if Weave.staging?
    end

    def self.filter_recipients(message, allowlist)
      return if allowlist.nil?

      dropped = []
      %i[to cc bcc].each do |field|
        addresses = Array(message.public_send(field))
        next if addresses.empty?

        kept, removed = addresses.partition { |address| allowed?(address, allowlist) }
        dropped.concat(removed)
        message.public_send(:"#{field}=", kept)
      end

      Rails.logger.info("MAIL_ALLOWLIST dropped recipients: #{dropped.join(', ')}") if dropped.any?
      return if [message.to, message.cc, message.bcc].any?(&:present?)

      message.perform_deliveries = false
      Rails.logger.info("MAIL_ALLOWLIST: no allowed recipients left, not delivering #{message.subject.inspect}")
    end

    def self.allowed?(address, allowlist)
      address = address.to_s.strip.downcase
      allowlist.any? { |entry| entry.start_with?("@") ? address.end_with?(entry) : address == entry }
    end

    def self.prefix_subject(message)
      message.subject = "#{SUBJECT_PREFIX}#{message.subject}" unless message.subject.to_s.start_with?(SUBJECT_PREFIX)
    end

    private_class_method :filter_recipients, :allowed?, :prefix_subject

  end
end
