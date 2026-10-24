# frozen_string_literal: true

require "rails_helper"

# Funder profiles are config only. The specs use test funders; no real funder
# is in config.
RSpec.describe FunderProfiles do
  def check(profile, program_funders: {})
    config = DataRetention.config.deep_dup
    config[:funders] = { probe: profile }.deep_symbolize_keys
    config[:program_funders] = program_funders.deep_symbolize_keys
    described_class.validate!(config)
  end

  def error_for(profile, **)
    check(profile, **)
    nil
  rescue described_class::InvalidConfig => e
    e.message
  end

  it "reads every key of a full profile" do
    profile = described_class.find!(:consent_funder)

    expect(profile).to have_attributes(
      name: "Consent Funder", contract_reference: "TEST-2027-001", financial_keep_years: 8, individual_record_years: nil,
      award_ends_on: Date.new(2030, 6, 30), post_award_keep_years: 6, report_fields: %w[age_band gender_identity],
      small_count_threshold: 5, amount_reporting: "totals", report_cadence: "quarterly", requires_member_consent: true
    )
    expect(profile.post_award_until).to eq(Date.new(2036, 6, 30))
    expect(profile.eligibility).to have_attributes(min_age: 13, max_age: 18, countries: %w[US CA])
  end

  it "gives defaults to a minimal profile" do
    profile = check({ name: "Minimal" }).sole

    expect(profile).to have_attributes(amount_reporting: "bands", report_cadence: "annual", requires_member_consent: false,
                                       report_fields: [], small_count_threshold: nil)
    expect(profile.threshold).to eq(DemographicsVault.small_count_threshold)
    expect(profile.eligibility.any?).to be(false)
  end

  it "has no real funder outside the test environment" do
    values = YAML.safe_load_file(Rails.root.join("config/kyc/data_retention.yml"), aliases: true, permitted_classes: [Date])

    %w[shared development production].each { |environment| expect(values.dig(environment, "funders")).to eq({}) }
  end

  it "validates the config at boot" do
    expect(Rails.root.join("config/initializers/funder_profiles.rb").read).to include("FunderProfiles.validate!")
  end

  it "refuses an unknown key, with the funder and the key in the message" do
    expect(error_for({ name: "X", retension_years: 3 })).to include("Funder probe", "unknown key retension_years")
  end

  it "refuses a missing name" do
    expect(error_for({ financial_keep_years: 3 })).to include("name is required")
  end

  it "refuses bad year values" do
    expect(error_for({ name: "X", financial_keep_years: -1 })).to include("financial_keep_years")
    expect(error_for({ name: "X", individual_record_years: "two" })).to include("individual_record_years")
    expect(error_for({ name: "X", post_award_keep_years: 2 })).to include("needs award_ends_on")
    expect(error_for({ name: "X", award_ends_on: "soon" })).to include("award_ends_on must be a date")
  end

  it "refuses a report field that is not in config/demographics.yml" do
    expect(error_for({ name: "X", report_fields: %w[age_band shoe_size] })).to include("shoe_size", "config/demographics.yml")
  end

  it "allows a stricter small-count threshold and refuses a lower one" do
    global = DemographicsVault.small_count_threshold

    expect(error_for({ name: "X", small_count_threshold: global + 5 })).to be_nil
    expect(error_for({ name: "X", small_count_threshold: global - 1 })).to include("only be stricter")
  end

  it "refuses an unknown amount setting, cadence or consent value" do
    expect(error_for({ name: "X", amount_reporting: "exact" })).to include("amount_reporting must be one of bands, totals")
    expect(error_for({ name: "X", report_cadence: "weekly" })).to include("report_cadence must be one of")
    expect(error_for({ name: "X", requires_member_consent: "yes" })).to include("true or false")
  end

  it "checks the eligibility terms" do
    expect(error_for({ name: "X", eligibility: { min_age: 13, region: "EU" } })).to include("unknown key region")
    expect(error_for({ name: "X", eligibility: { min_age: 20, max_age: 18 } })).to include("min_age is above max_age")
    expect(error_for({ name: "X", eligibility: { countries: %w[usa] } })).to include("two-letter country codes")
  end

  it "maps a program to a list of funders, and reads a single key as a list" do
    expect(error_for({ name: "X" }, program_funders: { ganymede: "probe" })).to be_nil
    expect(error_for({ name: "X" }, program_funders: { ganymede: %w[probe] })).to be_nil
  end

  it "refuses a program funder without a profile, and an unknown program" do
    expect(error_for({ name: "X" }, program_funders: { ganymede: %w[probe ghost] })).to include("no funder profile ghost")
    expect(error_for({ name: "X" }, program_funders: { callisto: %w[probe] })).to include("callisto is not a program")
  end

  it "lists the funders of a program and the programs of a funder" do
    with_funder_config(program_funders: { ganymede: %w[test_funder consent_funder] }) do
      expect(described_class.keys_for_program(:ganymede)).to eq(%w[test_funder consent_funder])
      expect(described_class.find!(:consent_funder).programs).to eq(["ganymede"])
      expect(DataRetention.funder_for_program(:ganymede)).to be_nil
    end
  end
end
