# frozen_string_literal: true

module DemographicsVault
  # Opens sealed envelopes with the private key. Only DemographicsReport uses
  # it, and it writes only aggregates (spec/security/demographics_vault_guard_spec.rb
  # fails if other code refers to it).
  #
  # The key comes only from the environment of the reporting run, never from
  # Rails credentials: every Weave process can read the credentials, and the
  # web app must not hold this key. See docs/KYC.md.
  class Reader
    ENV_PEM = "WEAVE_DEMOGRAPHICS_PRIVATE_KEY"
    ENV_FILE = "WEAVE_DEMOGRAPHICS_PRIVATE_KEY_FILE"

    # No private key in this process.
    class KeyUnavailable < StandardError; end

    def self.from_env(env = ENV)
      pem = env[ENV_PEM].presence
      pem ||= File.read(env[ENV_FILE]) if env[ENV_FILE].present?
      pem ||= DevelopmentKeys.private_pem if Rails.env.development?
      raise KeyUnavailable, "Set #{ENV_PEM} or #{ENV_FILE} for the reporting run" if pem.blank?

      new(pem)
    end

    def initialize(pem)
      @key = OpenSSL::PKey.read(pem)
      raise KeyUnavailable, "The key is not a private key" unless @key.private?
    end

    def key_id = Envelope.key_id(@key)

    def open(envelope, aad: Envelope::AAD) = Envelope.open(envelope, @key, aad:)

    # Seals data that only this key pair may read again, for example the
    # departed totals.
    def seal(payload, **) = Envelope.seal(payload, @key, **)

    # Never print the key.
    def inspect = "#<#{self.class.name} key_id=#{key_id}>"

  end
end
