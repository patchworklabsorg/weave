# frozen_string_literal: true

require "rails_helper"

# Each funder's report uses only that funder's rules. The test funders are in
# config/kyc/data_retention.yml (test). The global threshold in test is 3.
RSpec.describe FunderReport do
  # open_funder: no consent, bands, gender and age band, threshold 3.
  # consent_funder: consent, totals, threshold 5.
  let(:funders) do
    {
      open_funder: { name: "Open Funder", report_fields: %w[age_band gender_identity] },
      consent_funder: { name: "Consent Funder", report_fields: %w[age_band], small_count_threshold: 5, amount_reporting: "totals",
                        requires_member_consent: true
},
      narrow_funder: { name: "Narrow Funder", report_fields: %w[age_band], small_count_threshold: 4 }
    }
  end

  before { with_funder_config(funders:, program_funders: { ganymede: %w[open_funder consent_funder narrow_funder] }) { nil } }

  def member(gender, funder:, consent: false)
    user = create(:user, :verified, birthday: 20.years.ago.to_date)
    DemographicsVault.record(user, { "gender_identity" => gender })
    ProgramParticipation.record!(user, program: "ganymede", outcome: "granted", funder:)
    FunderConsent.give!(user, "consent_funder") if consent
    user
  end

  def run! = DemographicsReport.generate!(reader: demographics_reader, run_by: "spec")

  it "counts only the funder's members and only its report fields" do
    4.times { member("woman", funder: "open_funder") }
    create(:user, :verified).then { |user| DemographicsVault.record(user, { "gender_identity" => "man" }) }
    run!

    report = described_class.build("open_funder")

    expect(report.demographics["respondents"]).to eq(4)
    expect(report.demographics["fields"].keys).to contain_exactly("age_band", "gender_identity")
    expect(report.demographics["fields"]["gender_identity"]).to include("woman" => 4)
  end

  it "leaves out fields the funder may not receive" do
    5.times { member("woman", funder: "narrow_funder") }
    run!

    expect(described_class.build("narrow_funder").demographics["fields"].keys).to eq(["age_band"])
  end

  it "uses the funder's own, stricter threshold" do
    4.times { member("woman", funder: "consent_funder", consent: true) }
    run!

    expect(described_class.build("consent_funder").demographics["respondents"]).to be_nil

    member("woman", funder: "consent_funder", consent: true)
    run!
    expect(described_class.build("consent_funder").demographics["respondents"]).to eq(5)
  end

  it "counts a member for a consent funder only with a live consent" do
    5.times { member("woman", funder: "consent_funder", consent: true) }
    withdrawn = member("woman", funder: "consent_funder", consent: true)
    FunderConsent.withdraw!(withdrawn, "consent_funder")
    member("woman", funder: "consent_funder", consent: false)

    expect(described_class.member_ids(FunderProfiles.find!(:consent_funder)).size).to eq(5)
    run!
    expect(described_class.build("consent_funder").demographics["respondents"]).to eq(5)
  end

  it "leaves departed members and the delete-time aggregates out of a consent funder's report" do
    DeleteTimeAggregate.create!(program: "ganymede", year: 2026, outcome: "granted", age_band: "18-24", region: "US",
                                amount_band: "none", count: 12)

    report = described_class.build("consent_funder")

    expect(report.delete_time).to be_nil
    expect(report.notes.join).to include("consent")
    expect(described_class.build("open_funder").delete_time["ganymede-2026"]["respondents"]).to eq(12)
  end

  it "gives totals only, never a per-person amount, and hides a total of too few members" do
    users = Array.new(5) { member("woman", funder: "consent_funder", consent: true) }
    users.first(4).each { |user| create(:grant_disbursement, user:, funder: "consent_funder", amount_cents: 50_000, disbursed_on: Date.new(2026, 5, 1)) }

    hidden = described_class.build("consent_funder").amounts["ganymede-2026"]
    expect(hidden).to include("total_cents" => nil, "recipients" => nil)

    create(:grant_disbursement, user: users.last, funder: "consent_funder", amount_cents: 25_000, disbursed_on: Date.new(2026, 6, 1))
    shown = described_class.build("consent_funder").amounts["ganymede-2026"]
    expect(shown).to include("total_cents" => 225_000, "recipients" => 5)
    expect(shown.keys).to contain_exactly("total_cents", "recipients", "currency")
  end

  it "gives amount bands to a bands funder, suppressed" do
    Array.new(3) { member("woman", funder: "open_funder") }.each do |user|
      create(:grant_disbursement, user:, funder: "open_funder", amount_cents: 50_000, disbursed_on: Date.new(2026, 5, 1))
    end

    expect(described_class.build("open_funder").amounts["ganymede-2026"]["fields"]["amount_band"]).to eq("500-999" => 3)
  end

  it "does not count a record with no funder in a program with more than one funder" do
    user = create(:user, :verified)
    ProgramParticipation.create!(user:, program: "ganymede", year: 2026, outcome: "granted", funder: nil)

    expect(described_class.member_ids(FunderProfiles.find!(:open_funder))).to be_empty
  end

  it "says when no reporting run counted the funder yet" do
    expect(described_class.build("open_funder").notes.join).to include("No reporting run")
  end
end
