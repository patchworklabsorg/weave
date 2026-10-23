# frozen_string_literal: true

# The open values of data handling, takeout and deletion, from
# config/kyc/data_retention.yml (see docs/KYC.md). Retention windows live in
# config and not in code, so counsel can change them.
module DataRetention
  PATH = Rails.root.join("config/kyc/data_retention.yml")

  class << self
    def config = @config ||= Rails.application.config_for(PATH)

    def review_sla = config.dig(:deletion, :review_sla_days).days

    def complete_within = config.dig(:deletion, :complete_within_days).days

    def takeout_download_window = config.dig(:takeout, :download_days).days

    def takeout_cooldown = config.dig(:takeout, :cooldown_hours).hours

    def dormancy_cutoff = config.dig(:dormancy, :inactive_years).years

    # Largest first, for example [60, 7].
    def dormancy_warning_days = Array(config.dig(:dormancy, :warning_days_before)).map { |days| Integer(days) }.sort.reverse

    def verification_audit_window = config.dig(:verification_audit, :keep_years_after_deletion).years

    def guardian_contact_until_age = Integer(config.fetch(:guardian_contact_until_age))

    # The funder profiles (see FunderProfiles).
    def funders = FunderProfiles.all

    def funder(key) = FunderProfiles.find(key)

    # The funder keys of a program (a program can have more than one).
    def funders_for_program(program) = FunderProfiles.keys_for_program(program)

    # The one funder key of a program, or nil when it has none or more than
    # one. A record then keeps no single funder, and retention uses the
    # longest window of all the program's funders.
    def funder_for_program(program)
      keys = funders_for_program(program)
      keys.one? ? keys.first : nil
    end

    # The funders whose terms apply to a record: its own funder, or every
    # funder of its program when it has none.
    def applicable_funders(funder_key, program)
      return [funder(funder_key)].compact if funder_key.present?

      FunderProfiles.for_program(program)
    end

    # Years a disbursement is kept in full: the default, or longer when a
    # funder's terms say so. The longest window always wins.
    def financial_keep_years(funder_key = nil, program: nil)
      default = Integer(config.dig(:financial, :keep_years))
      ([default] + applicable_funders(funder_key, program).filter_map(&:financial_keep_years)).max
    end

    # The last day a disbursement is kept in full: the later of the
    # financial window and each funder's post-award window.
    def financial_retention_ends_on(disbursed_on, funder_key: nil, program: nil)
      ends = [disbursed_on + financial_keep_years(funder_key, program:).years]
      ends += applicable_funders(funder_key, program).filter_map(&:post_award_until)
      ends.max
    end

    # How long an individual participation record is kept after the account
    # is deleted (the longest window of the funders that require one), or
    # nil when no funder requires it.
    def individual_record_window(funder_key, program: nil)
      years = applicable_funders(funder_key, program).filter_map(&:individual_record_years).max
      years&.years
    end

    # The time until an individual participation record is kept, counted
    # from the deletion: the later of the individual window and the
    # post-award window of each funder that requires individual records. Nil
    # when no funder requires one.
    def individual_record_until(funder_key, program: nil, from: Time.current)
      keeping = applicable_funders(funder_key, program).select(&:keeps_individual_records?)
      return nil if keeping.empty?

      ends = keeping.map { |profile| from + profile.individual_record_years.years }
      ends += keeping.filter_map { |profile| profile.post_award_until&.end_of_day }
      ends.max
    end

    # The amount band of a sum of cents, for example "250-499". "none" is the
    # $0 band (no money). A sum under one whole unit goes to the smallest
    # band above zero.
    def amount_band(cents)
      return "none" if cents.nil? || cents.zero?

      units = [cents / 100, 1].max
      starts = Array(config.fetch(:amount_band_starts)).map { |start| Integer(start) }.sort
      index = starts.rindex { |start| units >= start } || 0
      upper = starts[index + 1]
      return "#{starts[index]}+" if upper.nil?

      upper - 1 == starts[index] ? starts[index].to_s : "#{starts[index]}-#{upper - 1}"
    end

    # For specs that change a value.
    def reset! = @config = nil

  end
end
