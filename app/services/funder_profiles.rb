# frozen_string_literal: true

# Funder profiles: what each funder's contract says about the records Weave
# keeps and the reports Weave gives them (see docs/KYC.md, "Funder
# profiles"). The profiles live in config/kyc/data_retention.yml under
# `funders`, and `program_funders` maps each program to a list of funder
# keys. Adding a funder needs only config.
#
# The config is checked at boot (config/initializers/funder_profiles.rb). An
# unknown key or a bad value raises InvalidConfig with the funder, the key and
# the reason, so a typo can't silently change a retention window or a report.
#
# Eligibility (min_age, max_age, countries) is recorded and reported only.
# Weave does not enforce it on members: grants stay manual.
module FunderProfiles
  class InvalidConfig < StandardError; end

  KEYS = %w[name contract_reference financial_keep_years individual_record_years award_ends_on post_award_keep_years
            report_fields small_count_threshold amount_reporting report_cadence requires_member_consent eligibility].freeze
  ELIGIBILITY_KEYS = %w[min_age max_age countries].freeze
  AMOUNT_REPORTING = %w[bands totals].freeze
  CADENCES = %w[monthly quarterly annual end_of_award].freeze
  DEFAULT_AMOUNT_REPORTING = "bands"
  DEFAULT_CADENCE = "annual"
  KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/

  Eligibility = Data.define(:min_age, :max_age, :countries) do
    def any? = !min_age.nil? || !max_age.nil? || countries.any?
  end

  Profile = Data.define(:key, :name, :contract_reference, :financial_keep_years, :individual_record_years, :award_ends_on,
                        :post_award_keep_years, :report_fields, :small_count_threshold, :amount_reporting, :report_cadence,
                        :requires_member_consent, :eligibility) do
    # True when the contract requires individual participation records after
    # the account is deleted.
    def keeps_individual_records? = !individual_record_years.nil?

    def consent_required? = requires_member_consent

    # The small-count threshold for this funder's report: its own, which is
    # never lower than the global one.
    def threshold = small_count_threshold || DemographicsVault.small_count_threshold

    # The last day of the post-award window, or nil.
    def post_award_until = (award_ends_on + post_award_keep_years.years if award_ends_on && post_award_keep_years)

    def programs = FunderProfiles.programs_for(key)

    def totals? = amount_reporting == "totals"
  end

  class << self
    def all = load(DataRetention.config)

    def find(key) = (all.find { |profile| profile.key == key.to_s } if key.present?)

    def find!(key) = find(key) || raise(KeyError, "No funder profile #{key}")

    # The funder keys of a program, in config order.
    def keys_for_program(program) = program_funders(DataRetention.config)[program.to_s] || []

    def for_program(program) = keys_for_program(program).filter_map { |key| find(key) }

    # The programs that list this funder.
    def programs_for(key) = program_funders(DataRetention.config).select { |_program, keys| keys.include?(key.to_s) }.keys

    # Checks the whole config. Raises InvalidConfig. Returns the profiles.
    def validate!(config = DataRetention.config) = load(config)

    private

    def load(config)
      funders = config.fetch(:funders, nil) || {}
      raise InvalidConfig, "funders must be a mapping of funder key to profile" unless funders.respond_to?(:to_h)

      profiles = funders.to_h.map { |key, values| build(key.to_s, values) }
      program_funders(config, known: profiles.map(&:key))
      profiles
    end

    def build(key, values)
      error = ->(message) { raise InvalidConfig, "Funder #{key}: #{message}" }
      error.call("the key must be lower case letters, digits and underscores") unless key.match?(KEY_FORMAT)
      error.call("the profile must be a mapping") unless values.respond_to?(:to_h)

      values = values.to_h.transform_keys(&:to_s)
      unknown = values.keys - KEYS
      error.call("unknown key #{unknown.join(', ')}. Allowed keys: #{KEYS.join(', ')}") if unknown.any?
      name = values["name"]
      error.call("name is required") unless name.is_a?(String) && name.strip.present?

      award_ends_on = date(values["award_ends_on"], error)
      post_award = years(values, "post_award_keep_years", error)
      error.call("post_award_keep_years needs award_ends_on") if post_award && award_ends_on.nil?

      Profile.new(
        key:, name: name.strip, contract_reference: optional_string(values["contract_reference"], "contract_reference", error),
        financial_keep_years: years(values, "financial_keep_years", error),
        individual_record_years: years(values, "individual_record_years", error),
        award_ends_on:, post_award_keep_years: post_award,
        report_fields: report_fields(values["report_fields"], error),
        small_count_threshold: threshold(values["small_count_threshold"], error),
        amount_reporting: choice(values, "amount_reporting", AMOUNT_REPORTING, DEFAULT_AMOUNT_REPORTING, error),
        report_cadence: choice(values, "report_cadence", CADENCES, DEFAULT_CADENCE, error),
        requires_member_consent: boolean(values["requires_member_consent"], error),
        eligibility: eligibility(values["eligibility"], error)
      )
    end

    def years(values, name, error)
      value = values[name]
      return nil if value.nil?

      error.call("#{name} must be a whole number of years above 0, or empty") unless value.is_a?(Integer) && value.positive?
      value
    end

    def date(value, error)
      return nil if value.nil?
      return value if value.is_a?(Date)

      Date.iso8601(value.to_s)
    rescue Date::Error
      error.call("award_ends_on must be a date (YYYY-MM-DD), or empty")
    end

    def optional_string(value, name, error)
      return nil if value.nil?

      error.call("#{name} must be text") unless value.is_a?(String)
      value.strip.presence
    end

    # Only fields that the demographics vault holds: the age band and the
    # questions in config/demographics.yml.
    def report_fields(value, error)
      return [] if value.nil?

      error.call("report_fields must be a list") unless value.is_a?(Array)
      fields = value.map(&:to_s)
      allowed = allowed_report_fields
      unknown = fields - allowed
      error.call("report_fields has #{unknown.join(', ')}, which is not in config/demographics.yml. Allowed: #{allowed.join(', ')}") if unknown.any?
      fields.uniq
    end

    def allowed_report_fields = ["age_band"] + DemographicsVault.fields.map { |field| field[:key].to_s }

    def threshold(value, error)
      return nil if value.nil?

      global = DemographicsVault.small_count_threshold
      error.call("small_count_threshold must be a whole number") unless value.is_a?(Integer)
      error.call("small_count_threshold (#{value}) can only be stricter than the global value (#{global}), never lower") if value < global
      value
    end

    def choice(values, name, allowed, default, error)
      value = values[name]
      return default if value.nil?

      error.call("#{name} must be one of #{allowed.join(', ')}") unless allowed.include?(value.to_s)
      value.to_s
    end

    def boolean(value, error)
      return false if value.nil?

      error.call("requires_member_consent must be true or false") unless [true, false].include?(value)
      value
    end

    def eligibility(value, error)
      return Eligibility.new(min_age: nil, max_age: nil, countries: []) if value.nil?

      error.call("eligibility must be a mapping") unless value.respond_to?(:to_h)
      value = value.to_h.transform_keys(&:to_s)
      unknown = value.keys - ELIGIBILITY_KEYS
      error.call("eligibility has the unknown key #{unknown.join(', ')}. Allowed: #{ELIGIBILITY_KEYS.join(', ')}") if unknown.any?
      min_age, max_age = %w[min_age max_age].map do |name|
        age = value[name]
        error.call("eligibility.#{name} must be a whole number of 0 or more") unless age.nil? || (age.is_a?(Integer) && age >= 0)
        age
      end
      error.call("eligibility.min_age is above max_age") if min_age && max_age && min_age > max_age
      countries = value["countries"] || []
      unless countries.is_a?(Array) && countries.all? { |code| code.to_s.match?(/\A[A-Z]{2}\z/) }
        error.call("eligibility.countries must be a list of two-letter country codes (for example US)")
      end
      Eligibility.new(min_age:, max_age:, countries: countries.map(&:to_s))
    end

    # program key => [funder keys]. A single key is read as a list of one.
    def program_funders(config, known: nil)
      raw = config.fetch(:program_funders, nil) || {}
      raise InvalidConfig, "program_funders must be a mapping of program to a list of funder keys" unless raw.respond_to?(:to_h)

      raw.to_h.to_h do |program, keys|
        list = Array(keys).map(&:to_s)
        if known
          unless KnotSettings.program_keys.include?(program.to_s)
            raise InvalidConfig, "program_funders: #{program} is not a program in config/kyc/knot.yml"
          end
          missing = list - known
          raise InvalidConfig, "program_funders.#{program}: no funder profile #{missing.join(', ')}" if missing.any?
        end
        [program.to_s, list]
      end
    end

  end
end
