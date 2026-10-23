# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppAccess, "identity verification gate" do # rubocop:disable RSpec/DescribeMethod
  let(:user) { create(:user, :verified, :accepted_code_of_conduct) }
  let(:application) do
    Doorkeeper::Application.create!(name: "Ganymede", redirect_uri: "https://ganymede.example.com/cb", access_policy: "everyone")
  end

  it "is off by default, so the community is not gated" do
    expect(application.requires_verification).to be(false)
    expect(described_class.permitted?(user, application)).to be(true)
  end

  it "refuses a member who is not verified when the app opts in" do
    application.update!(requires_verification: true)

    decision = described_class.explain(user, application)

    expect(decision).not_to be_permitted
    expect(decision.to_s).to eq("Has not passed identity verification")
  end

  it "refuses a member whose attempt is still in progress" do
    application.update!(requires_verification: true)
    create(:verification, :call_scheduled, user:)

    expect(described_class.permitted?(user, application)).to be(false)
  end

  it "lets a verified member in" do
    application.update!(requires_verification: true)
    create(:verification, :verified, user:)

    expect(described_class.permitted?(user, application)).to be(true)
  end

  it "has no admin bypass" do
    application.update!(requires_verification: true)

    expect(described_class.permitted?(create(:user, :owner, :accepted_code_of_conduct), application)).to be(false)
  end
end
