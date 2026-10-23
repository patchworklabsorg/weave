# frozen_string_literal: true

require "rails_helper"

RSpec.describe KnotGrants do
  let(:lead) { create(:user, :admin, :patch_lead) }
  let(:board) { create(:user, :admin, is_board: true) }
  let(:knot) { create(:knot, :with_audit) }
  let(:member) { knot.user }

  def with_programs(programs)
    allow(KnotSettings).to receive(:config).and_return({ programs: })
  end

  before do
    with_programs(ganymede: { name: "Project Ganymede", grant_cap: 1 })
    lead
  end

  it "reads the locked Ganymede cap of 1 from config" do
    allow(KnotSettings).to receive(:config).and_call_original
    KnotSettings.reset!

    expect(KnotSettings.program("ganymede").grant_cap).to eq(1)
  end

  describe ".record" do
    it "records one grant, keyed to the Knot, with an audit row" do
      result = described_class.record(member, program: "ganymede", by: lead)

      expect(result).to be_success
      expect(result.grant.knot).to eq(knot)
      expect(knot.audit_verification.events.pluck(:kind)).to include("program_grant_recorded")
    end

    it "enforces the cap" do
      described_class.record(member, program: "ganymede", by: lead)

      result = described_class.record(member, program: "ganymede", by: lead)

      expect(result.errors[:base]).to eq(I18n.t("knot.grants.cap_reached"))
      expect(knot.program_grants.count).to eq(1)
      expect(described_class.remaining(member, "ganymede")).to eq(0)
    end

    it "treats a nil cap as no cap" do
      with_programs(ganymede: { name: "Project Ganymede", grant_cap: nil })

      3.times { described_class.record(member, program: "ganymede", by: lead) }

      expect(knot.program_grants.count).to eq(3)
      expect(described_class.remaining(member, "ganymede")).to be_nil
    end

    it "refuses a blacklisted Knot, a member with no Knot and an unknown program" do
      expect(described_class.eligibility(create(:user), "ganymede")).to eq(:not_verified)
      expect(described_class.eligibility(member, "callisto")).to eq(:unknown_program)
      knot.update!(blacklisted: true)
      expect(described_class.record(member, program: "ganymede", by: lead)).not_to be_success
    end

    it "lets only the patch lead or an owner record" do
      expect(described_class.record(member, program: "ganymede", by: create(:user, :superadmin))).not_to be_success
      expect(described_class.record(member, program: "ganymede", by: create(:user, :owner))).to be_success
    end
  end

  describe "an override over the cap" do
    before { create(:program_grant, knot:) }

    it "needs the patch lead to ask with a reason and a board member to sign off" do
      result = described_class.request_override(member, program: "ganymede", by: lead, reason: "New, unrelated project.")
      request = knot.change_requests.sole

      expect(result).to be_success
      expect(KnotChanges.sign_off(request, by: create(:user, :identity_team))).not_to be_success
      expect(KnotChanges.sign_off(request, by: lead)).not_to be_success

      expect(KnotChanges.sign_off(request, by: board)).to be_success
      expect(knot.program_grants.count).to eq(2)
      expect(knot.audit_verification.events.find_by(kind: "knot_change_requested").data)
        .to include("change" => "grant_override", "reason" => "New, unrelated project.")
    end

    it "is only for the patch lead, only over the cap, and never for a blacklisted Knot" do
      expect(described_class.request_override(member, program: "ganymede", by: board, reason: "x")).not_to be_success
      knot.program_grants.delete_all
      expect(described_class.request_override(member, program: "ganymede", by: lead, reason: "x").errors[:base])
        .to eq(I18n.t("knot.grants.override_not_needed"))
      create(:program_grant, knot:)
      knot.update!(blacklisted: true)
      expect(described_class.request_override(member, program: "ganymede", by: lead, reason: "x")).not_to be_success
    end
  end
end
