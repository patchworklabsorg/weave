# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeleteTimeAggregates do
  let(:bands) do
    described_class::Bands.new(program: "ganymede", year: 2026, outcome: "granted", age_band: "16-17", region: "US",
                               amount_band: "250-499")
  end

  it "adds one to a cell, and keeps no row per person" do
    3.times { described_class.add!(bands) }

    expect(DeleteTimeAggregate.count).to eq(1)
    expect(DeleteTimeAggregate.sole.count).to eq(3)
  end

  it "uses the amount band of the member's disbursements in that program and year, never the amount" do
    user = create(:user, :verified)
    participation = create(:program_participation, user:, year: Date.current.year)
    create(:grant_disbursement, user:, amount_cents: 30_000)

    result = described_class.bands_for(participation, user:)

    expect(result.amount_band).to eq("250-499")
    expect(result.region).to eq("unknown")
  end

  it "reads the totals through the vault's small-count suppression" do
    threshold = DemographicsVault.small_count_threshold
    threshold.times { described_class.add!(bands) }
    described_class.add!(bands.with(outcome: "withdrawn"))

    report = described_class.report

    cohort = report["cohorts"]["ganymede-2026"]
    expect(report["threshold"]).to eq(threshold)
    expect(cohort["respondents"]).to eq(threshold + 1)
    expect(cohort["fields"]["outcome"]).to eq("granted" => nil, "withdrawn" => nil)
  end

  it "hides every count when the cohort is under the threshold" do
    described_class.add!(bands)

    fields = {
      "outcome" => { "granted" => nil }, "age_band" => { "16-17" => nil }, "region" => { "US" => nil },
      "amount_band" => { "250-499" => nil }
    }
    expect(described_class.report["all"]).to eq("respondents" => nil, "fields" => fields)
  end
end
