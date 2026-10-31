# frozen_string_literal: true

require "rails_helper"

RSpec.describe StagingTestStates do
  let(:owner) { create(:user, :owner, :verified) }
  let(:member) { create(:user, :verified) }

  before { allow(Weave).to receive(:staging?).and_return(true) }

  it "refuses outside staging" do
    allow(Weave).to receive(:staging?).and_return(false)

    expect { described_class.set!(member, area: "identity", state: "verified", by: owner) }
      .to raise_error(StagingTestStates::Error)
    expect(member.verifications).to be_empty
  end

  it "refuses a superadmin who is not an owner" do
    superadmin = create(:user, :superadmin, :verified)

    expect { described_class.set!(member, area: "identity", state: "verified", by: superadmin) }
      .to raise_error(StagingTestStates::Error)
  end

  it "refuses an unknown state" do
    expect { described_class.set!(member, area: "identity", state: "call_scheduled", by: owner) }
      .to raise_error(StagingTestStates::Error, "Unknown test state.")
  end

  it "passes identity verification, then asks for a new call" do
    described_class.set!(member, area: "identity", state: "verified", by: owner)
    expect(member.reload.verification_status).to eq("verified")
    expect(member.knot).to be_present

    described_class.set!(member, area: "identity", state: "reverification_required", by: owner)
    expect(member.reload.latest_verification).to be_reverification_required
    expect(member.verification_status).to eq("needs_submission")
    expect(member.verifications.count).to eq(1)
  end

  it "fails identity verification, then clears it" do
    described_class.set!(member, area: "identity", state: "verified", by: owner)
    described_class.set!(member, area: "identity", state: "failed", by: owner)
    expect(member.reload.latest_verification).to be_failed
    expect(member.knot).to be_nil

    described_class.set!(member, area: "identity", state: "none", by: owner)
    expect(member.reload.verifications).to be_empty
    expect(VerificationEvent.where(user_id: member.id)).to be_empty
  end

  it "sets US residency" do
    described_class.set!(member, area: "residency", state: "us_resident", by: owner, us_state: "CA")
    expect(member.us_residency_status).to eq("us_resident")
    expect(ResidencyFlow.current_check(member).us_state).to eq("CA")

    described_class.set!(member, area: "residency", state: "not_us_resident", by: owner)
    expect(member.us_residency_status).to eq("not_us_resident")

    described_class.set!(member, area: "residency", state: "none", by: owner)
    expect(member.us_residency_status).to eq("needs_check")
  end

  it "sets guardian consent for a member under 18, even for the owner's peers" do
    minor = create(:user, :owner, :verified, :minor)

    described_class.set!(minor, area: "guardian_consent", state: "verified", by: owner)
    expect(minor.reload.guardian_verified?).to be(true)

    described_class.set!(minor, area: "guardian_consent", state: "none", by: owner)
    expect(minor.reload.guardian_consent_missing?).to be(true)
  end

  it "refuses guardian consent for an adult" do
    expect { described_class.set!(member, area: "guardian_consent", state: "granted", by: owner) }
      .to raise_error(StagingTestStates::Error, /under 18/)
  end
end
