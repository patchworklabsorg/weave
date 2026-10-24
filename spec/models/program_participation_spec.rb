# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: program_participations
# Database name: primary
#
#  id             :bigint           not null, primary key
#  age_band       :string
#  amount_band    :string
#  detached_at    :datetime
#  funder         :string
#  outcome        :string           not null
#  program        :string           not null
#  region         :string
#  retained_until :datetime
#  year           :integer          not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  user_id        :bigint
#
# Indexes
#
#  index_program_participations_on_retained_until                (retained_until)
#  index_program_participations_on_user_id                       (user_id)
#  index_program_participations_on_user_id_and_program_and_year  (user_id,program,year) UNIQUE WHERE (user_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
RSpec.describe ProgramParticipation do
  let(:user) { create(:user, :verified) }

  it "records one row per program and year, and updates the outcome" do
    described_class.record!(user, program: "ganymede", outcome: "accepted")
    row = described_class.record!(user, program: "ganymede", outcome: "completed")

    expect(described_class.where(user:).count).to eq(1)
    expect(row.outcome).to eq("completed")
    # ganymede has two test funders, so the row names none.
    expect(row.funder).to be_nil
  end

  it "keeps the one funder of a program, or the funder it is given" do
    with_funder_config(program_funders: { ganymede: %w[test_funder] }) do
      expect(described_class.record!(user, program: "ganymede", outcome: "accepted").funder).to eq("test_funder")
    end
  end

  it "takes a named funder of the program, and refuses another" do
    row = described_class.record!(user, program: "ganymede", outcome: "accepted", funder: "plain_funder")

    expect(row.funder).to eq("plain_funder")
    expect(build(:program_participation, funder: "consent_funder")).not_to be_valid
  end

  it "keeps a record with no funder for the longest window of the program's funders" do
    expect(build(:program_participation, funder: nil).individual_record_window).to eq(2.years)
  end

  it "rejects an unknown program or outcome" do
    expect(build(:program_participation, program: "nope")).not_to be_valid
    expect(build(:program_participation, outcome: "won")).not_to be_valid
  end

  it "is recorded when a patch lead records a grant" do
    owner = create(:user, :owner, :verified)
    create(:knot, user:)

    result = KnotGrants.record(user, program: "ganymede", by: owner)

    expect(result).to be_success
    expect(described_class.find_by(user:, program: "ganymede").outcome).to eq("granted")
  end

  it "keeps an individual record only when the funder requires one" do
    expect(build(:program_participation, :funder_required).individual_record_window).to eq(2.years)
    expect(build(:program_participation).individual_record_window).to be_nil
  end
end
