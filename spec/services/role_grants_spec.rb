# frozen_string_literal: true

require "rails_helper"

# Grants and revokes of staff and identity roles, and the immediate rules
# from config/roles.yml. The proposal rules are in identity_governance_spec.
RSpec.describe RoleGrants do
  include ActiveJob::TestHelper

  let(:owner) { create(:user, :owner, :verified, first_name: "Olive") }
  let(:superadmin) { create(:user, :superadmin, :verified) }
  let(:admin) { create(:user, :admin, :verified) }
  let(:member) { create(:user, :verified, first_name: "Mia") }

  describe "staff and contractor: any admin, at once" do
    %w[staff contractor].each do |key|
      it "lets an admin grant and revoke #{key} for a person they manage" do
        expect(described_class.grant(member, key, by: admin, reason: "Hired")).to be_success
        expect(member.reload.has_role?(key)).to be(true)
        expect(UserRole.active.for_role(key).sole).to have_attributes(user: member, granted_by: admin, reason: "Hired")

        expect(described_class.revoke(member, key, by: admin, reason: "Left")).to be_success
        expect(member.reload.has_role?(key)).to be(false)
        expect(UserRole.for_role(key).sole).to have_attributes(revoked_by: admin, revoke_reason: "Left", revoked_at: be_present)
      end

      it "does not let a plain member, or an admin for a peer, grant or revoke #{key}" do
        peer = create(:user, :admin, :verified)
        holder = create(:user, :verified, "is_#{key}": true)

        expect(described_class.grant(member, key, by: create(:user, :verified))).not_to be_success
        expect(described_class.grant(peer, key, by: admin)).not_to be_success
        expect(described_class.revoke(holder, key, by: create(:user, :verified), reason: "x")).not_to be_success
        expect([member, peer].map { |user| user.reload.has_role?(key) }).to all(be(false))
        expect(holder.reload.has_role?(key)).to be(true)
      end
    end

    it "refuses a second grant of a role the person holds" do
      described_class.grant(member, "staff", by: admin)

      expect(described_class.grant(member, "staff", by: admin).message).to include("already has this role")
      expect(UserRole.count).to eq(1)
    end
  end

  describe "board: any owner, at once, for any person, logged and emailed" do
    it "lets an owner change the board role of another owner, which skips the peer rule of the other roles" do # rubocop:disable RSpec/MultipleExpectations
      other_owner = create(:user, :owner, :verified)

      expect(described_class.grant(other_owner, "board", by: owner)).to be_success
      expect(other_owner.reload.board?).to be(true)
      expect(IdentityGovernanceEvent.last).to have_attributes(kind: "board_member_added", actor: owner, subject: other_owner)
      expect(PrivilegedAttributeChange.where(user_id: other_owner.id).last).to have_attributes(role_key: "board", actor_id: owner.id)
      expect(described_class.revoke(other_owner, "board", by: owner, reason: "Term ended")).to be_success
      expect(other_owner.reload.board?).to be(false)

      expect(described_class.grant(other_owner, "staff", by: owner)).not_to be_success
      expect(UserAdminPermissions.new(owner, other_owner).change_board?).to be(true)
    end

    it "lets an owner grant and revoke, with a governance event and an email to the board" do # rubocop:disable RSpec/MultipleExpectations
      sitting = create(:user, :verified, is_board: true)

      perform_enqueued_jobs { expect(described_class.grant(member, "board", by: owner)).to be_success }
      expect(member.reload.board?).to be(true)
      expect(IdentityGovernanceEvent.last).to have_attributes(kind: "board_member_added", actor: owner, subject: member)
      expect(ActionMailer::Base.deliveries.flat_map(&:to)).to include(sitting.email, member.email)

      expect(described_class.revoke(member, "board", by: owner, reason: "Term ended")).to be_success
      expect(member.reload.board?).to be(false)
      expect(IdentityGovernanceEvent.last).to have_attributes(kind: "board_member_removed", actor: owner, subject: member)
    end

    it "does not let an admin or a superadmin grant or revoke it" do
      board = create(:user, :verified, is_board: true)

      [admin, superadmin].each do |actor|
        expect(described_class.grant(member, "board", by: actor)).not_to be_success
        expect(described_class.grant(actor, "board", by: actor)).not_to be_success
        expect(described_class.revoke(board, "board", by: actor, reason: "x")).not_to be_success
      end
      expect(member.reload.board?).to be(false)
      expect(board.reload.board?).to be(true)
      expect(IdentityGovernanceEvent.count).to eq(0)
    end
  end

  describe "patch lead removal: one owner, at once" do
    let(:lead) { create(:user, :verified, :patch_lead) }

    it "lets an owner remove a patch lead of one program" do
      expect(described_class.revoke(lead, "patch_lead", scope: "ganymede", by: owner, reason: "Stepped down")).to be_success

      expect(lead.reload.has_role?("patch_lead", scope: "ganymede")).to be(false)
      expect(KnotGrants.patch_lead?(lead, "ganymede")).to be(false)
    end

    it "does not let an admin remove a patch lead, and needs a proposal to add one" do
      expect(described_class.revoke(lead, "patch_lead", scope: "ganymede", by: admin, reason: "x")).not_to be_success
      expect(described_class.grant(member, "patch_lead", scope: "ganymede", by: owner).message)
        .to include("needs a proposal on the identity governance page")
      expect(lead.reload.has_role?("patch_lead", scope: "ganymede")).to be(true)
    end
  end

  describe "verifier removal: one owner or identity lead, at once" do
    let(:verifier) { create(:user, :key_holder) }

    it "lets an owner or a lead remove a verifier through IdentityGovernance, with the roles that need it" do
      lead = create(:user, :verified, identity_team: true, identity_lead: true)

      expect(described_class.revoke(verifier, "verifier", by: lead, reason: "Left")).to be_success
      expect(verifier.reload).to have_attributes(identity_team: false, identity_key_holder: false)
      expect(IdentityGovernanceEvent.last).to have_attributes(kind: "member_removed", actor: lead, subject: verifier)

      other = create(:user, :identity_team)
      expect(described_class.revoke(other, "verifier", by: owner, reason: "Left")).to be_success
    end

    it "does not let a board member who is not an owner remove a verifier" do
      board = create(:user, :admin, :verified, is_board: true)

      expect(described_class.revoke(verifier, "verifier", by: board, reason: "x")).not_to be_success
      expect(verifier.reload.identity_team).to be(true)
    end
  end

  describe "the roles with a proposal rule" do
    it "refuses an immediate grant or revoke, even for an owner" do
      verifier = create(:user, :key_holder)

      expect(described_class.grant(member, "verifier", by: owner)).not_to be_success
      expect(described_class.grant(verifier, "identity_lead", by: owner)).not_to be_success
      expect(described_class.revoke(verifier, "key_holder", by: owner, reason: "x")).not_to be_success
      expect(verifier.reload).to have_attributes(identity_key_holder: true, identity_lead: false)
    end
  end

  describe "the rules come from config/roles.yml" do
    it "follows a changed rule with no code change" do
      raw = YAML.safe_load_file(RoleRegistry::PATH)
      raw["roles"]["staff"]["grant"]["rule"] = "owner"
      allow(RoleRegistry).to receive(:definitions).and_return(RoleRegistry.parse(raw))

      expect(described_class.grant(member, "staff", by: admin)).not_to be_success
      expect(described_class.grant(member, "staff", by: owner)).to be_success
      expect(described_class.rule_text("staff", :grant)).to eq("One owner, at once.")
    end
  end

  describe ".grant! and .revoke!" do
    it "checks the scope of the role" do
      expect { described_class.grant!(member, "patch_lead") }.to raise_error(described_class::Error, /needs a scope/)
      expect { described_class.grant!(member, "patch_lead", scope: "europa") }.to raise_error(described_class::Error, /needs a scope/)
      expect { described_class.grant!(member, "staff", scope: "ganymede") }.to raise_error(described_class::Error, /takes no scope/)
      expect { described_class.grant!(member, "wizard") }.to raise_error(ArgumentError, /Unknown role/)
    end

    it "needs the required roles first, and revokes the roles that need a revoked role" do
      expect { described_class.grant!(member, "key_holder") }.to raise_error(described_class::Error, /must be verifier first/)

      described_class.grant!(member, "verifier")
      described_class.grant!(member, "key_holder")
      described_class.grant!(member, "identity_lead")
      described_class.revoke!(member, "verifier", reason: "Left")

      expect(member.reload.role_keys).to be_empty
      expect(UserRole.where(user: member).pluck(:revoke_reason)).to all(eq("Left"))
    end

    it "keeps at most the configured number of key holders" do
      create_list(:user, VerificationSettings.max_key_holders, :key_holder)
      described_class.grant!(member, "verifier")

      expect { described_class.grant!(member, "key_holder") }.to raise_error(described_class::Error, /already 3 key holders/)
    end

    it "returns the active row for a second grant, and lets a revoked role be granted again" do
      first = described_class.grant!(member, "staff")
      expect(described_class.grant!(member, "staff")).to eq(first)

      described_class.revoke!(member, "staff")
      described_class.grant!(member, "staff")

      expect(UserRole.where(user: member).count).to eq(2)
      expect(UserRole.active.where(user: member).count).to eq(1)
    end

    it "gives one person the same scoped role for two programs" do
      allow(KnotSettings).to receive(:config).and_return(
        { programs: { ganymede: { name: "Project Ganymede", grant_cap: 1 }, europa: { name: "Project Europa", grant_cap: 1 } } }
      )

      described_class.grant!(member, "patch_lead", scope: "ganymede")
      described_class.grant!(member, "patch_lead", scope: "europa")
      described_class.revoke!(member, "patch_lead", scope: "ganymede")

      expect(member.reload.role_scopes("patch_lead")).to eq(["europa"])
    end

    it "keeps the system groups in line after the commit" do
      described_class.grant!(member, "staff")
      expect(member.groups.pluck(:slug)).to include("staff")

      described_class.revoke!(member, "staff")
      expect(member.reload.groups.pluck(:slug)).not_to include("staff")
    end

    it "names the actor in the permanent log" do
      described_class.grant!(member, "staff", by: admin)
      PrivilegedChangeActor.with(label: "console jasper") { described_class.revoke!(member, "staff") }

      grant, revoke = PrivilegedAttributeChange.where(user_id: member.id).order(:id).to_a
      expect(grant).to have_attributes(operation: "grant", role_key: "staff", actor_id: admin.id, actor_label: "user #{admin.p_id}")
      expect(revoke).to have_attributes(operation: "revoke", role_key: "staff", actor_id: nil, actor_label: "console jasper")
      expect(PrivilegedChangeActor.current).to eq(["", ""])
    ensure
      PrivilegedChangeActor.clear!
    end
  end

  describe "account deletion" do
    it "revokes every role and keeps the rows" do
      user = create(:user, :verified, is_staff: true, is_board: true)
      ids = UserRole.where(user:).ids

      user.destroy!

      rows = UserRole.where(id: ids)
      expect(rows.count).to eq(2)
      expect(rows.pluck(:user_id)).to all(be_nil)
      expect(rows.pluck(:revoke_reason)).to all(eq("The account was deleted."))
    end
  end
end
