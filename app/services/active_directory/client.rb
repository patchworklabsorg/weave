# frozen_string_literal: true

require "net/ldap"
require "timeout"

module ActiveDirectory
  # The account Weave found for a user: an AD user whose employeeID is the
  # user's p_id.
  Entry = Data.define(:dn, :user_principal_name, :employee_id)

  class Error < StandardError; end

  # No domain controller answered in time, TLS failed, or the service account
  # could not bind. Callers fail closed on this error.
  class Unavailable < Error; end

  # More than one AD account carries the same employeeID. Weave does not
  # guess which one is right.
  class AmbiguousLink < Error; end

  # Talks LDAPS to the domain controllers. This is the only class that knows
  # LDAP. It returns plain symbols, so the rest of Weave never sees an LDAP
  # result code.
  #
  # Every operation tries the hosts in order (loom, then spindle) and moves to
  # the next host only on a transport problem: a refused or dropped
  # connection, a timeout, or a TLS failure. An answer from a DC (for example
  # "wrong password") is final, so a failed bind is never repeated on the
  # second DC and does not count twice toward the AD lockout threshold.
  class Client
    # AD puts a Win32 error in the bind diagnostic text: "... data 52e, v4563".
    BIND_ERRORS = {
      "525" => :invalid_credentials,  # user not found
      "52e" => :invalid_credentials,  # wrong password
      "530" => :restricted,           # not permitted to log on at this time
      "531" => :restricted,           # not permitted to log on at this workstation
      "532" => :password_expired,
      "533" => :disabled,
      "701" => :account_expired,
      "773" => :must_change_password,
      "775" => :locked
    }.freeze

    INVALID_CREDENTIALS = 49
    CONSTRAINT_VIOLATION = 19
    INSUFFICIENT_ACCESS = 50
    UNWILLING_TO_PERFORM = 53

    TRANSPORT_ERRORS = [
      Net::LDAP::Error, SystemCallError, SocketError, IOError, OpenSSL::SSL::SSLError, Timeout::Error
    ].freeze

    SEARCH_ATTRIBUTES = %w[distinguishedName userPrincipalName employeeID].freeze

    attr_reader :config

    # ldap_factory builds a Net::LDAP-like object for one host. Tests pass a
    # fake. Production uses #build_ldap.
    def initialize(config: Config.current, ldap_factory: nil, logger: Rails.logger)
      @config = config
      @ldap_factory = ldap_factory || method(:build_ldap)
      @logger = logger
    end

    # Finds the AD user whose employeeID equals employee_id, under the base DN.
    # Returns nil when there is none. Raises Unavailable or AmbiguousLink.
    def find_employee(employee_id)
      return nil if employee_id.blank?

      # equals, not eq: it escapes the value, so "*" or ")" can not widen the filter.
      filter = Net::LDAP::Filter.eq("objectCategory", "person") &
               Net::LDAP::Filter.eq("objectClass", "user") &
               Net::LDAP::Filter.equals("employeeID", employee_id.to_s)

      entries = with_service_connection do |ldap|
        results = ldap.search(base: config.base_dn, filter: filter, attributes: SEARCH_ATTRIBUTES, return_result: true)
        raise Unavailable, "search failed (#{describe(ldap)})" if results.nil?

        results
      end

      raise AmbiguousLink, "#{entries.size} AD accounts have employeeID #{employee_id}" if entries.size > 1
      return nil if entries.empty?

      to_entry(entries.first)
    end

    # employeeID values of every AD user under base. For the rake task that
    # puts the members of a sponsored-project OU into a Weave group.
    def employee_ids_under(base)
      filter = Net::LDAP::Filter.eq("objectCategory", "person") &
               Net::LDAP::Filter.eq("objectClass", "user") &
               Net::LDAP::Filter.present("employeeID")

      with_service_connection do |ldap|
        results = ldap.search(base: base, filter: filter, attributes: %w[employeeID], return_result: true)
        raise Unavailable, "search failed (#{describe(ldap)})" if results.nil?

        results.filter_map { |entry| first(entry, :employeeid) }
      end
    end

    # Checks a password with a simple bind as the user. Returns :ok or one of
    # the BIND_ERRORS values. An empty password is refused here: AD treats a
    # simple bind with no password as an anonymous bind, which "succeeds".
    def authenticate(entry, password)
      return :invalid_credentials if password.blank?

      with_failover do |host|
        ldap = @ldap_factory.call(host, { method: :simple, username: entry.dn, password: password })
        if ldap.bind
          :ok
        else
          bind_failure(ldap)
        end
      end
    end

    # Self-service change: AD checks the current password and applies its
    # password history rules. Sent as one modify with a delete of the old
    # value and an add of the new value.
    def change_password(entry, current:, new:)
      return :invalid_current_password if current.blank?

      operations = [
        [:delete, :unicodePwd, [self.class.encode_password(current)]],
        [:add, :unicodePwd, [self.class.encode_password(new)]]
      ]
      write_password(entry, operations)
    end

    # Admin reset or forgotten-password reset: a replace, which needs the
    # service account's Reset Password right.
    def reset_password(entry, new)
      write_password(entry, [[:replace, :unicodePwd, [self.class.encode_password(new)]]])
    end

    # unicodePwd is the password in double quotes, encoded as UTF-16LE.
    def self.encode_password(password)
      "\"#{password}\"".encode(Encoding::UTF_16LE).b
    end

    private

    def write_password(entry, operations)
      with_service_connection do |ldap|
        if ldap.modify(dn: entry.dn, operations: operations)
          :ok
        else
          write_failure(ldap)
        end
      end
    end

    def with_service_connection
      with_failover do |host|
        ldap = @ldap_factory.call(host, { method: :simple, username: config.bind_dn, password: config.bind_password })
        unless ldap.bind
          # A wrong or locked service account is a configuration problem. Do
          # not try the next DC: the same account would fail there too.
          @logger.error("[active_directory] service account bind failed on #{host}: #{describe(ldap)}")
          raise Unavailable, "service account bind failed"
        end

        yield ldap
      end
    end

    def with_failover
      raise Unavailable, "Active Directory is not configured" unless config.usable?

      errors = []
      config.hosts.each do |host|
        return Timeout.timeout(config.timeout) { yield host }
      rescue Unavailable
        raise
      rescue *TRANSPORT_ERRORS => e
        @logger.warn("[active_directory] #{host}:#{config.port} failed: #{e.class}: #{e.message}")
        errors << "#{host}: #{e.class}"
      end

      raise Unavailable, "no domain controller answered (#{errors.join(', ')})"
    end

    def build_ldap(host, auth)
      Net::LDAP.new(
        host: host,
        port: config.port,
        auth: auth,
        connect_timeout: config.connect_timeout,
        encryption: { method: :simple_tls, tls_options: config.tls_options }
      )
    end

    def bind_failure(ldap)
      result = ldap.get_operation_result
      message = result.error_message.to_s
      data = message[/data ([0-9a-f]+)/i, 1]&.downcase

      if result.code.to_i == INVALID_CREDENTIALS || data
        BIND_ERRORS.fetch(data, :invalid_credentials)
      else
        @logger.warn("[active_directory] unexpected bind result #{result.code}: #{message}")
        :invalid_credentials
      end
    end

    # 0000052D: the new password breaks the password policy (length,
    # complexity, history, minimum age). 00000056: the current password is
    # wrong.
    def write_failure(ldap)
      result = ldap.get_operation_result
      message = result.error_message.to_s.upcase

      return :policy_rejected if message.include?("0000052D")
      return :invalid_current_password if message.include?("00000056")

      @logger.warn("[active_directory] password write failed #{result.code}: #{result.error_message}")
      case result.code.to_i
      when INSUFFICIENT_ACCESS, UNWILLING_TO_PERFORM then :not_permitted
      when CONSTRAINT_VIOLATION then :policy_rejected
      else :failed
      end
    end

    def describe(ldap)
      result = ldap.get_operation_result
      "#{result.code} #{result.message} #{result.error_message}".strip
    end

    def to_entry(entry)
      Entry.new(
        dn: entry.dn.to_s,
        user_principal_name: first(entry, :userprincipalname),
        employee_id: first(entry, :employeeid)
      )
    end

    def first(entry, attribute)
      Array(entry[attribute]).first&.to_s
    end

  end
end
