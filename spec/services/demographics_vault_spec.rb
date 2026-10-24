# frozen_string_literal: true

require "rails_helper"

RSpec.describe DemographicsVault do
  let(:user) { create(:user, :verified, birthday: Date.new(2009, 3, 1)) }

  # Acts as the reporting run, which holds the private key.
  def opened(record) = demographics_reader.open(record.envelope)

  around { |example| travel_to(Date.new(2026, 10, 12)) { example.run } }

  describe ".record" do
    it "seals the answers so that only the private key opens them" do
      result = described_class.record(user, { "gender_identity" => "woman" }, consent: true)

      expect(result).to be_success
      record = DemographicRecord.find_by!(user:)
      expect(record.envelope).not_to include("woman", "gender", "16-17")
      expect(opened(record)).to eq(
        "v" => 1, "age_band" => "16-17", "recorded_year" => 2026,
        "answers" => { "gender_identity" => "woman", "gender_identity_self_description" => nil }
      )
    end

    it "derives the age band from the birthday when the member saves" do
      described_class.record(user, {}, consent: true)
      travel_to(Date.new(2027, 3, 1))
      described_class.record(user, {}, consent: true)

      expect(opened(DemographicRecord.find_by!(user:))["age_band"]).to eq("18-24")
    end

    it "makes envelopes of the same size, whatever the answers" do
      described_class.record(user, { "gender_identity" => "prefer_not_to_say" }, consent: true)
      short = DemographicRecord.find_by!(user:).envelope.bytesize
      described_class.record(user, { "gender_identity" => "self_describe", "gender_identity_self_description" => "x" * 100 }, consent: true)

      expect(DemographicRecord.find_by!(user:).envelope.bytesize).to eq(short)
    end

    it "replaces the answers before, with no copy left" do
      described_class.record(user, { "gender_identity" => "woman" }, consent: true)
      described_class.record(user, { "gender_identity" => "non_binary" }, consent: true)

      expect(DemographicRecord.where(user:).count).to eq(1)
      expect(opened(DemographicRecord.find_by!(user:))["answers"]["gender_identity"]).to eq("non_binary")
    end

    it "needs the member to agree" do
      result = described_class.record(user, { "gender_identity" => "woman" }, consent: false)

      expect(result.errors).to include(:consent)
      expect(DemographicRecord.where(user:)).to be_empty
    end

    it "refuses an option that is not in the config" do
      result = described_class.record(user, { "gender_identity" => "robot" }, consent: true)

      expect(result.errors).to include(:gender_identity)
      expect(DemographicRecord.where(user:)).to be_empty
    end

    it "keeps the self-description only when the member picks self_describe" do
      described_class.record(user, { "gender_identity" => "man", "gender_identity_self_description" => "stray" }, consent: true)
      expect(opened(DemographicRecord.find_by!(user:))["answers"]["gender_identity_self_description"]).to be_nil

      described_class.record(user, { "gender_identity" => "self_describe", "gender_identity_self_description" => " genderfluid " }, consent: true)
      expect(opened(DemographicRecord.find_by!(user:))["answers"]["gender_identity_self_description"]).to eq("genderfluid")
    end

    it "stores a skipped question as no answer" do
      described_class.record(user, {}, consent: true)

      expect(opened(DemographicRecord.find_by!(user:))["answers"]["gender_identity"]).to be_nil
    end

    context "with a multi-answer field from the config" do
      before do
        allow(described_class).to receive(:fields).and_return(
          [{ key: "heritage", type: "multi", options: %w[a b c] }]
        )
      end

      it "keeps every answer the member picks" do
        described_class.record(user, { "heritage" => %w[a c] }, consent: true)

        expect(opened(DemographicRecord.find_by!(user:))["answers"]).to eq("heritage" => %w[a c])
      end

      it "keeps only prefer_not_to_say when the member also picks it" do
        described_class.record(user, { "heritage" => %w[a prefer_not_to_say] }, consent: true)

        expect(opened(DemographicRecord.find_by!(user:))["answers"]).to eq("heritage" => ["prefer_not_to_say"])
      end

      it "refuses an unknown answer" do
        expect(described_class.record(user, { "heritage" => %w[a z] }, consent: true).errors).to include(:heritage)
      end
    end

    it "raises without a public key" do
      described_class.public_key = nil

      expect(described_class).not_to be_available
      expect { described_class.record(user, {}, consent: true) }.to raise_error(DemographicsVault::NotConfigured)
    end
  end

  describe ".withdraw!" do
    it "deletes the member's answers" do
      described_class.record(user, { "gender_identity" => "woman" }, consent: true)

      expect(described_class.withdraw!(user)).to be(true)
      expect(DemographicRecord.where(user:)).to be_empty
      expect(DemographicFold.count).to eq(0)
    end

    it "is false when there is nothing to delete" do
      expect(described_class.withdraw!(user)).to be(false)
    end
  end

  describe ".answered_at" do
    it "tells when the member last answered, and nothing more" do
      expect(described_class.answered_at(user)).to be_nil

      described_class.record(user, {}, consent: true)

      expect(described_class.answered_at(user)).to be_within(1.second).of(Time.current)
    end
  end

  describe ".fold!" do
    it "parks the sealed envelope with no link to the member, then destroys the record" do
      described_class.record(user, { "gender_identity" => "woman" }, consent: true)
      envelope = DemographicRecord.find_by!(user:).envelope

      fold = described_class.fold!(user, cohorts: ["ganymede-2026", "2026"])

      expect(fold.folded).to be(true)
      expect(DemographicRecord.where(user:)).to be_empty
      parked = DemographicFold.sole
      expect(parked).to have_attributes(envelope:, cohorts: ["ganymede-2026", "2026"])
      expect(DemographicFold.column_names).not_to include("user_id", "created_at", "updated_at")
      # A random id, so the row order does not show the order of deletions.
      expect(parked.id).to match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
    end

    it "defaults the cohort to the year" do
      described_class.record(user, {}, consent: true)

      described_class.fold!(user)

      expect(DemographicFold.sole.cohorts).to eq([Date.current.year.to_s])
    end

    it "does nothing for a member with no answers, and is safe to call twice" do
      expect(described_class.fold!(user).folded).to be(false)

      described_class.record(user, {}, consent: true)
      described_class.fold!(user)

      expect(described_class.fold!(user).folded).to be(false)
      expect(DemographicFold.count).to eq(1)
    end

    it "runs when a user is destroyed" do
      described_class.record(user, { "gender_identity" => "man" }, consent: true)

      user.destroy!

      expect(DemographicRecord.count).to eq(0)
      expect(DemographicFold.count).to eq(1)
    end
  end

  describe ".age_band" do
    it "bands ages with the configured starts" do
      today = Date.new(2026, 10, 12)

      expect(described_class.age_band(Date.new(2013, 10, 12), on: today)).to eq("13-15")
      expect(described_class.age_band(Date.new(2010, 10, 13), on: today)).to eq("13-15")
      expect(described_class.age_band(Date.new(2010, 10, 12), on: today)).to eq("16-17")
      expect(described_class.age_band(Date.new(2008, 10, 12), on: today)).to eq("18-24")
      expect(described_class.age_band(Date.new(2000, 1, 1), on: today)).to eq("25-34")
      expect(described_class.age_band(Date.new(1991, 10, 12), on: today)).to eq("35+")
      expect(described_class.age_band(nil, on: today)).to eq("unknown")
      expect(described_class.age_band(Date.new(2020, 1, 1), on: today)).to eq("0-12")
    end

    it "uses the locked bands: under 13, 13-15, 16-17, 18-24, 25-34, 35+" do
      expect(described_class.config.fetch(:age_band_starts)).to eq([0, 13, 16, 18, 25, 35])
    end
  end
end
