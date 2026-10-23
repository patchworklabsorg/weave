# frozen_string_literal: true

require "rails_helper"

RSpec.describe FunderConsent do
  let(:member) { create(:user, :verified) }

  it "gives consent once, and a withdrawal keeps the history" do
    first = described_class.give!(member, "consent_funder")
    expect(described_class.give!(member, "consent_funder")).to eq(first)

    described_class.withdraw!(member, "consent_funder")
    expect(first.reload.withdrawn_at).to be_present
    expect(described_class.user_ids_for("consent_funder")).to be_empty

    described_class.give!(member, "consent_funder")
    expect(member.funder_consents.count).to eq(2)
    expect(described_class.user_ids_for("consent_funder").pluck(:user_id)).to eq([member.id])
  end

  it "takes consent only for a funder that asks for it" do
    expect { described_class.give!(member, "test_funder") }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it "goes with the account" do
    described_class.give!(member, "consent_funder")

    DeletionPipeline.run!(create(:deletion_request, :approved, user: member))

    expect(described_class.count).to eq(0)
  end

  it "is in the account data of a takeout" do
    described_class.give!(member, "consent_funder")

    data = Takeout.build(member)

    expect(data.dig("categories", "account_profile", "data", "funder_consents").sole).to include("funder" => "Consent Funder")
  end
end
