# frozen_string_literal: true

require "rails_helper"

RSpec.describe DemographicsReport do
  # The test threshold (config/demographics.yml) is 3.
  def departed_totals
    demographics_reader.open(DemographicDepartedTotal.sole.envelope, aad: described_class::DEPARTED_AAD)
  end

  def answer(gender, birthday: 20.years.ago.to_date)
    user = create(:user, :verified, birthday:)
    DemographicsVault.record(user, { "gender_identity" => gender })
    user
  end

  describe ".generate!" do
    it "saves counts with small counts hidden" do
      4.times { answer("woman") }
      3.times { answer("man") }
      answer("non_binary")

      report = described_class.generate!(reader: demographics_reader, run_by: "spec")

      expect(report.active["respondents"]).to eq(8)
      # non_binary (1) is hidden, so the next smallest (man, 3) is hidden too.
      expect(report.active["fields"]["gender_identity"]).to eq("woman" => 4, "man" => nil, "non_binary" => nil)
      expect(report.active["fields"]["age_band"]).to eq("18-24" => 8)
      expect(report).to have_attributes(threshold: 3, run_by: "spec", unreadable_count: 0)
    end

    it "never stores the self-described text" do
      user = create(:user, :verified)
      DemographicsVault.record(user, { "gender_identity" => "self_describe", "gender_identity_self_description" => "stargazer" })
      3.times { answer("self_describe") }

      report = described_class.generate!(reader: demographics_reader)

      expect(report.results.to_json).not_to include("stargazer")
      expect(report.active["fields"]["gender_identity"]).to eq("self_describe" => 4)
    end

    it "hides everything when there are fewer respondents than the threshold" do
      2.times { answer("woman") }

      report = described_class.generate!(reader: demographics_reader)

      expect(report.active["respondents"]).to be_nil
      expect(report.active["fields"]["gender_identity"]).to eq("woman" => nil)
    end

    it "counts a record from before every question was required as not answered" do
      3.times do
        payload = { "v" => 1, "age_band" => "18-24", "recorded_year" => 2026, "answers" => { "gender_identity" => nil } }
        key = DemographicsVault.public_key
        DemographicRecord.create!(user: create(:user, :verified), envelope: DemographicsVault::Envelope.seal(payload, key),
                                  key_id: DemographicsVault::Envelope.key_id(key))
      end

      report = described_class.generate!(reader: demographics_reader)

      expect(report.active["fields"]["gender_identity"]).to eq("not_answered" => 3)
    end

    it "counts parked envelopes of deleted members into their cohorts, then deletes them" do
      users = Array.new(3) { answer("woman") }
      users.each { |user| DemographicsVault.fold!(user, cohorts: ["ganymede-2026"]) }
      answer("man").destroy!

      report = described_class.generate!(reader: demographics_reader)

      expect(DemographicFold.count).to eq(0)
      expect(report.folds_counted).to eq(4)
      expect(report.departed["ganymede-2026"]["respondents"]).to eq(3)
      expect(report.departed["ganymede-2026"]["fields"]["gender_identity"]).to eq("woman" => 3)
      expect(report.departed[Date.current.year.to_s]["respondents"]).to be_nil
      expect(departed_totals["ganymede-2026"]).to include("respondents" => 3)
    end

    it "keeps the raw departed totals sealed in the database" do
      3.times { DemographicsVault.fold!(answer("woman"), cohorts: ["ganymede-2026"]) }
      DemographicsVault.fold!(answer("man"), cohorts: ["ganymede-2026"])

      described_class.generate!(reader: demographics_reader)

      row = DemographicDepartedTotal.sole
      expect(row.envelope).not_to include("ganymede", '"woman"', '"man"', "gender_identity")
      expect(row.key_id).to eq(demographics_reader.key_id)
      expect(departed_totals["ganymede-2026"]["fields"]["gender_identity"]).to eq("woman" => 3, "man" => 1)
      expect { demographics_reader.open(row.envelope) }.to raise_error(DemographicsVault::Envelope::Unreadable)
    end

    it "adds to the departed totals across runs" do
      3.times { DemographicsVault.fold!(answer("woman"), cohorts: ["c"]) }
      described_class.generate!(reader: demographics_reader)
      DemographicsVault.fold!(answer("woman"), cohorts: ["c"])

      report = described_class.generate!(reader: demographics_reader)

      expect(report.departed["c"]["fields"]["gender_identity"]).to eq("woman" => 4)
    end

    it "does not count a parked envelope that another run counted first" do
      3.times { DemographicsVault.fold!(answer("woman"), cohorts: ["c"]) }
      first = DemographicFold.first
      reader = demographics_reader
      allow(reader).to receive(:open).and_wrap_original do |original, envelope|
        DemographicFold.where(id: first.id).delete_all if envelope == first.envelope
        original.call(envelope)
      end

      report = described_class.generate!(reader:)

      expect(report.folds_counted).to eq(2)
      expect(departed_totals["c"]["respondents"]).to eq(2)
    end

    it "keeps an envelope it can't open, and counts it as unreadable" do
      answer("woman")
      DemographicsVault.fold!(answer("man"), cohorts: ["c"])
      other_key = DemographicsVault::Reader.new(OpenSSL::PKey::RSA.generate(2048).private_to_pem)

      report = described_class.generate!(reader: other_key)

      expect(report.unreadable_count).to eq(2)
      expect(DemographicFold.count).to eq(1)
      expect(DemographicDepartedTotal.count).to eq(0)
    end

    it "stops, and changes nothing, when the departed totals need another key" do
      3.times { DemographicsVault.fold!(answer("woman"), cohorts: ["c"]) }
      described_class.generate!(reader: demographics_reader)
      sealed = DemographicDepartedTotal.sole.envelope
      DemographicsVault.fold!(answer("man"), cohorts: ["c"])
      other_key = DemographicsVault::Reader.new(OpenSSL::PKey::RSA.generate(2048).private_to_pem)

      expect { described_class.generate!(reader: other_key) }
        .to raise_error(described_class::DepartedTotalsUnreadable)
      expect(DemographicDepartedTotal.sole.envelope).to eq(sealed)
      expect(DemographicFold.count).to eq(1)
      expect(DemographicReport.count).to eq(1)
    end
  end

  describe ".suppress" do
    it "shows zero counts and counts at the threshold" do
      result = described_class.suppress({ "respondents" => 6, "fields" => { "f" => { "a" => 3, "b" => 3, "c" => 0 } } }, 3)

      expect(result["fields"]["f"]).to eq("a" => 3, "b" => 3, "c" => 0)
    end

    it "does not hide a second count when two or more are already hidden" do
      result = described_class.suppress({ "respondents" => 12, "fields" => { "f" => { "a" => 1, "b" => 2, "c" => 9 } } }, 3)

      expect(result["fields"]["f"]).to eq("a" => nil, "b" => nil, "c" => 9)
    end
  end
end
