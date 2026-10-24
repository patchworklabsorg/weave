# frozen_string_literal: true

require "rails_helper"

RSpec.describe DataRetention do
  it "reads the locked values from config" do # rubocop:disable RSpec/MultipleExpectations
    expect(described_class.review_sla).to eq(14.days)
    expect(described_class.complete_within).to eq(30.days)
    expect(described_class.dormancy_cutoff).to eq(5.years)
    expect(described_class.dormancy_warning_days).to eq([60, 7])
    expect(described_class.verification_audit_window).to eq(3.years)
    expect(described_class.financial_keep_years).to eq(7)
    expect(described_class.guardian_contact_until_age).to eq(18)
  end

  it "uses the longer financial window when a funder's terms say so" do
    expect(described_class.financial_keep_years("test_funder")).to eq(10)
    expect(described_class.financial_keep_years("plain_funder")).to eq(7)
    expect(described_class.financial_keep_years("unknown")).to eq(7)
  end

  it "keeps individual records only for funders that require them" do
    expect(described_class.individual_record_window("test_funder")).to eq(2.years)
    expect(described_class.individual_record_window("plain_funder")).to be_nil
    expect(described_class.funders_for_program("ganymede")).to eq(%w[test_funder plain_funder])
  end

  it "uses the longest window of all the funders of a program when a record names none" do
    with_funder_config(program_funders: { ganymede: %w[test_funder consent_funder] }) do
      expect(described_class.funder_for_program("ganymede")).to be_nil
      expect(described_class.financial_keep_years(nil, program: "ganymede")).to eq(10)
      expect(described_class.financial_keep_years("consent_funder", program: "ganymede")).to eq(8)
      expect(described_class.individual_record_window(nil, program: "ganymede")).to eq(2.years)
    end
  end

  it "keeps a disbursement until the later of the financial and the post-award window" do
    early = Date.new(2026, 1, 15)

    expect(described_class.financial_retention_ends_on(early, funder_key: "consent_funder")).to eq(Date.new(2036, 6, 30))
    expect(described_class.financial_retention_ends_on(Date.new(2030, 1, 1), funder_key: "consent_funder")).to eq(Date.new(2038, 1, 1))
    expect(described_class.financial_retention_ends_on(early, funder_key: "plain_funder")).to eq(Date.new(2033, 1, 15))
  end

  it "keeps an individual record until the later of its windows, and only for funders that require one" do
    with_funder_config(funders: { keeper: { name: "Keeper", individual_record_years: 2, award_ends_on: "2031-12-31", post_award_keep_years: 3 } },
                       program_funders: { ganymede: %w[keeper] }) do
      from = Time.zone.local(2027, 3, 1)
      expect(described_class.individual_record_until("keeper", from:)).to eq(Date.new(2034, 12, 31).end_of_day)
      expect(described_class.individual_record_until("keeper", from: Time.zone.local(2034, 6, 1))).to eq(Time.zone.local(2036, 6, 1))
    end
  end

  it "keeps no individual record for a funder that does not require one" do
    expect(described_class.individual_record_until("consent_funder")).to be_nil
  end

  it "bands an amount, never the figure" do # rubocop:disable RSpec/MultipleExpectations
    expect(described_class.amount_band(0)).to eq("none")
    expect(described_class.amount_band(nil)).to eq("none")
    expect(described_class.amount_band(50)).to eq("1-99")
    expect(described_class.amount_band(9_999)).to eq("1-99")
    expect(described_class.amount_band(10_000)).to eq("100-249")
    expect(described_class.amount_band(30_000)).to eq("250-499")
    expect(described_class.amount_band(50_000)).to eq("500-999")
    expect(described_class.amount_band(100_000)).to eq("1000-2499")
    expect(described_class.amount_band(499_999)).to eq("2500-4999")
    expect(described_class.amount_band(900_000)).to eq("5000+")
    expect(described_class.config.fetch(:amount_band_starts)).to eq([0, 1, 100, 250, 500, 1000, 2500, 5000])
  end

  it "has a name and a legal basis text for every category" do
    DataCategories::ALL.each do |category|
      expect(category.name).not_to include("translation missing")
      expect(category.legal_basis).not_to include("translation missing", "%{")
    end
    expect(DataCategories.find("verification_audit").legal_basis).to include("3 years")
  end
end
