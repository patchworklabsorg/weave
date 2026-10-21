# frozen_string_literal: true

module ActiveDirectory
  # Connection settings for the Patchwork Active Directory, read from ENV
  # first and then from the `active_directory` credentials. See
  # docs/ACTIVE_DIRECTORY.md for every key.
  #
  # The feature is off unless `enabled` is true AND every required value is
  # present AND the CA bundle file exists. TLS verification can't be turned
  # off: there is no setting for it.
  class Config
    DEFAULT_HOSTS = %w[loom.patchwork.internal spindle.patchwork.internal].freeze
    DEFAULT_PORT = 636
    DEFAULT_BASE_DN = "OU=Patchwork,DC=patchwork,DC=internal"
    DEFAULT_CONNECT_TIMEOUT = 5
    DEFAULT_TIMEOUT = 10

    attr_reader :hosts, :port, :base_dn, :bind_dn, :ca_file, :connect_timeout, :timeout

    def self.current(env: ENV, credentials: Rails.application.credentials)
      new(env: env, credentials: credentials)
    end

    def initialize(env: ENV, credentials: Rails.application.credentials)
      @env = env
      @credentials = credentials
      @enabled = ActiveModel::Type::Boolean.new.cast(value("AD_ENABLED", :enabled)) || false
      @hosts = list(value("AD_HOSTS", :hosts)).presence || DEFAULT_HOSTS
      @port = (value("AD_PORT", :port).presence || DEFAULT_PORT).to_i
      @base_dn = value("AD_BASE_DN", :base_dn).presence || DEFAULT_BASE_DN
      @bind_dn = value("AD_BIND_DN", :bind_dn).presence
      @ca_file = value("AD_CA_FILE", :ca_file).presence
      @connect_timeout = (value("AD_CONNECT_TIMEOUT", :connect_timeout).presence || DEFAULT_CONNECT_TIMEOUT).to_f
      @timeout = (value("AD_TIMEOUT", :timeout).presence || DEFAULT_TIMEOUT).to_f
    end

    def enabled? = @enabled

    # True when Weave may talk to AD at all.
    def usable? = enabled? && missing.empty?

    # Names of required settings that are absent. For logs and the doctor task.
    def missing
      names = []
      names << "AD_BIND_DN" if bind_dn.blank?
      names << "AD_BIND_PASSWORD_FILE or AD_BIND_PASSWORD" if bind_password.blank?
      names << "AD_CA_FILE (a readable file)" unless ca_file.present? && File.file?(ca_file) && File.readable?(ca_file)
      names << "AD_HOSTS" if hosts.empty?
      names
    end

    # The service account password. Read each time, so a rotated secret file
    # takes effect without a restart. Never logged.
    def bind_password
      file = @env["AD_BIND_PASSWORD_FILE"].presence
      return File.read(file).chomp if file && File.file?(file) && File.readable?(file)

      @env["AD_BIND_PASSWORD"].presence || @credentials.dig(:active_directory, :bind_password).presence
    end

    # Options for OpenSSL::SSL::SSLContext#set_params. The peer certificate
    # must chain to the configured CA bundle, and net-ldap checks the host
    # name (post_connection_check) because verify_mode is not VERIFY_NONE.
    def tls_options
      {
        ca_file: ca_file,
        verify_mode: OpenSSL::SSL::VERIFY_PEER,
        verify_hostname: true,
        min_version: OpenSSL::SSL::TLS1_2_VERSION
      }
    end

    def inspect = "#<#{self.class.name} enabled=#{enabled?} hosts=#{hosts.inspect} port=#{port} base_dn=#{base_dn.inspect}>"

    private

    def value(env_key, credential_key)
      @env[env_key].presence || @credentials.dig(:active_directory, credential_key)
    end

    def list(raw)
      Array(raw).flat_map { |entry| entry.to_s.split(",") }.map(&:strip).reject(&:empty?)
    end

  end
end
