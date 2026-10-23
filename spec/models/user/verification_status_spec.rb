# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, "verification status" do # rubocop:disable RSpec/DescribeMethod
  let(:user) { create(:user, :verified) }

  it "is not a column: Weave derives it each time" do
    expect(described_class.column_names).not_to include("verification_status")
  end

  it "needs a submission with no attempt" do
    expect(user.verification_status).to eq("needs_submission")
  end

  it "is pending while an attempt is in progress" do
    create(:verification, :call_scheduled, user:)

    expect(user.verification_status).to eq("pending")
  end

  it "needs a submission after a document problem" do
    create(:verification, user:, status: "needs_resubmission", resubmission_note: "Blurry")

    expect(user.verification_status).to eq("needs_submission")
  end

  it "needs a submission after a failed call" do
    create(:verification, :failed, user:)

    expect(user.verification_status).to eq("needs_submission")
  end

  it "is pending while the lead reviews an escalation" do
    create(:verification, :failed, user:, escalated_at: 1.hour.ago)

    expect(user.verification_status).to eq("pending")
  end

  it "is ineligible when the lead closed the case" do
    create(:verification, :failed, user:, escalated_at: 2.hours.ago, escalation_resolved_at: 1.hour.ago,
                                   escalation_resolution: "ineligible", escalation_note: "Repeated fraud")

    expect(user.verification_status).to eq("ineligible")
  end

  it "is verified when the last attempt passed" do
    first = create(:verification, :failed, user:, created_at: 1.month.ago)
    create(:verification, :verified, user:, previous_attempt: first)

    expect(user.verification_status).to eq("verified")
    expect(user.identity_verified?).to be(true)
  end

  describe "identity team roles" do
    it "needs identity team membership for a key holder or a lead" do
      user.assign_attributes(identity_key_holder: true, identity_lead: true)

      expect(user).not_to be_valid
      expect(user.errors[:identity_key_holder]).to be_present
      expect(user.errors[:identity_lead]).to be_present
    end

    it "allows at most the configured number of key holders" do
      create_list(:user, VerificationSettings.max_key_holders, :key_holder)

      third = build(:user, :key_holder)

      expect(third).not_to be_valid
      expect(third.errors[:identity_key_holder].first).to include("already")
    end
  end
end
