# frozen_string_literal: true

require "ostruct"

# A stand-in for the Patchwork Active Directory. It answers like a domain
# controller (result codes and the "data 52e" diagnostic text) without a
# network, so the specs cover every AD answer that Weave handles.
#
#   directory = FakeDirectory.new
#   directory.add_user(user.p_id, password: "Correct-horse-1")
#   use_fake_directory(directory)
class FakeDirectory
  SERVICE_DN = "CN=svc-weave-ldap,OU=Service Accounts,OU=Patchwork,DC=patchwork,DC=internal"
  SERVICE_PASSWORD = "service-secret"
  BASE_DN = "OU=Patchwork,DC=patchwork,DC=internal"

  Account = Struct.new(:dn, :employee_id, :password, :bind_error, :upn, keyword_init: true)

  attr_reader :accounts, :binds, :modifications, :down_hosts, :slow_hosts
  attr_accessor :modify_error, :service_password

  def initialize
    @accounts = []
    @binds = []
    @modifications = []
    @down_hosts = []
    @slow_hosts = []
    @modify_error = nil
    @service_password = SERVICE_PASSWORD
  end

  # bind_error is the AD data code a bind returns even with the right
  # password, for example "533" (disabled) or "773" (must change).
  def add_user(employee_id, password:, ou: "OU=Users", bind_error: nil, name: employee_id)
    dn = "CN=#{name},#{ou},#{BASE_DN}"
    account = Account.new(dn: dn, employee_id: employee_id, password: password, bind_error: bind_error, upn: "#{name.downcase}@patchwork.internal")
    @accounts << account
    account
  end

  def account(employee_id) = @accounts.find { |account| account.employee_id == employee_id }

  # The ldap_factory that ActiveDirectory::Client calls for each host.
  def call(host, auth)
    raise Errno::ECONNREFUSED, host if down_hosts.include?(host)

    Connection.new(self, host, auth)
  end

  def config(env = {})
    ActiveDirectory::Config.new(
      env: {
        "AD_ENABLED"       => "true",
        "AD_HOSTS"         => "loom.patchwork.internal,spindle.patchwork.internal",
        "AD_BIND_DN"       => SERVICE_DN,
        "AD_BIND_PASSWORD" => SERVICE_PASSWORD,
        "AD_CA_FILE"       => FakeDirectory.ca_file,
        "AD_TIMEOUT"       => "1"
      }.merge(env),
      credentials: {}
    )
  end

  def client(env = {}) = ActiveDirectory::Client.new(config: config(env), ldap_factory: self, logger: Logger.new(nil))

  def self.ca_file
    @ca_file ||= Rails.root.join("tmp/fake-ad-ca.pem").tap { |path| File.write(path, "test CA bundle\n") }.to_s
  end

  class Connection
    def initialize(directory, host, auth)
      @directory = directory
      @host = host
      @auth = auth
      @result = OpenStruct.new(code: 0, message: "Success", error_message: "")
    end

    attr_reader :host

    def bind
      sleep 2 if @directory.slow_hosts.include?(@host)
      @directory.binds << [@host, @auth[:username]]
      @bound_as = nil

      if @auth[:username] == SERVICE_DN
        return succeed(:service) if @auth[:password] == @directory.service_password

        return invalid_credentials("52e")
      end

      account = @directory.accounts.find { |candidate| candidate.dn == @auth[:username] }
      return invalid_credentials("525") if account.nil?
      return invalid_credentials("775") if account.bind_error == "775"
      return invalid_credentials("52e") unless account.password == @auth[:password]
      return invalid_credentials(account.bind_error) if account.bind_error

      succeed(account)
    end

    def search(base:, filter:, attributes:, return_result:)
      text = filter.to_s
      employee_id = text[/employeeID=([^)*]+)\)/, 1]
      matches = @directory.accounts.select { |account| account.dn.end_with?(base) }
      matches = matches.select { |account| account.employee_id == employee_id } if employee_id

      matches.map do |account|
        entry = Net::LDAP::Entry.new(account.dn)
        entry[:employeeid] = account.employee_id
        entry[:userprincipalname] = account.upn
        entry
      end
    end

    def modify(dn:, operations:)
      @directory.modifications << { host: @host, dn: dn, operations: operations }
      if (error = @directory.modify_error)
        @result = OpenStruct.new(code: error.fetch(:code), message: "Error", error_message: error.fetch(:message))
        return false
      end

      account = @directory.accounts.find { |candidate| candidate.dn == dn }
      deleted = operations.find { |operation| operation.first == :delete }
      if deleted && FakeDirectory.decode(deleted.last.first) != account.password
        @result = OpenStruct.new(code: 19, message: "Constraint Violation",
                                 error_message: "00000056: AtrErr: DSID-03191083, #1:\n\t0: 00000056: DSID-03191083, problem 1005 (CONSTRAINT_ATT_TYPE), data 0, Att 9005a (unicodePwd)\n")
        return false
      end

      added = operations.find { |operation| %i[add replace].include?(operation.first) }
      account.password = FakeDirectory.decode(added.last.first)
      account.bind_error = nil if %w[773 532].include?(account.bind_error)
      true
    end

    def get_operation_result = @result

    private

    def succeed(who)
      @bound_as = who
      @result = OpenStruct.new(code: 0, message: "Success", error_message: "")
      true
    end

    def invalid_credentials(data)
      @result = OpenStruct.new(
        code: 49, message: "Invalid Credentials",
        error_message: "80090308: LdapErr: DSID-0C09044E, comment: AcceptSecurityContext error, data #{data}, v4563\u0000"
      )
      false
    end

  end

  # The inverse of ActiveDirectory::Client.encode_password.
  def self.decode(value)
    value.dup.force_encoding(Encoding::UTF_16LE).encode(Encoding::UTF_8).delete_prefix("\"").delete_suffix("\"")
  end

end

module FakeDirectoryHelpers
  def use_fake_directory(directory = FakeDirectory.new, env: {})
    DirectoryPasswords.client = directory.client(env)
    directory
  end
end

RSpec.configure do |config|
  config.include FakeDirectoryHelpers
  config.after { DirectoryPasswords.client = nil }
end
