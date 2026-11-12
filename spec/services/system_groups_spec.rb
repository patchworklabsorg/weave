# frozen_string_literal: true

require "rails_helper"

RSpec.describe SystemGroups do
  def group(slug) = Group.find_by!(slug: slug)

  def slugs_for(user) = user.reload.groups.pluck(:slug)

  describe ".ensure_groups!" do
    it "creates each system group once" do
      expect { described_class.ensure_groups! }.to change(Group.system, :count).by(SystemGroups::SLUGS.size)
      expect { described_class.ensure_groups! }.not_to change(Group, :count)
    end
  end

  describe "the user callback" do
    it "puts a new user in the groups that match their attributes" do
      user = create(:user, :admin, is_staff: true, is_board: true)

      expect(slugs_for(user)).to contain_exactly("everyone", "staff", "board", "admins")
      expect(user.group_memberships).to all(be_system)
    end

    it "puts a plain member in the everyone group only" do
      expect(slugs_for(create(:user))).to contain_exactly("everyone")
    end

    it "keeps every user in the everyone group" do
      user = create(:user, is_staff: true)
      user.update!(is_staff: false)

      expect(slugs_for(user)).to include("everyone")
    end

    {
      "staff"         => { is_staff: true },
      "board"         => { is_board: true },
      "contractors"   => { is_contractor: true },
      "admins"        => { role: :superadmin },
      "slack-members" => { slack_membership: "member" },
      "identity-team" => { role: :admin, identity_team: true }
    }.each do |slug, attributes|
      it "adds and removes #{slug} membership as the attribute changes" do
        user = create(:user)

        user.update!(attributes)
        expect(slugs_for(user)).to include(slug)

        reverted = attributes.to_h { |key, _| [key, User.new.public_send(key)] }
        user.update!(reverted)
        expect(slugs_for(user)).not_to include(slug)
      end
    end

    it "does not run when an unrelated attribute changes" do
      user = create(:user, is_staff: true)

      expect(described_class).not_to receive(:sync)
      user.update!(first_name: "Changed")
    end
  end

  describe "patch-leads" do
    let(:owner) { create(:user, :owner) }

    it "follows the patch lead role, for any patch" do
      user = create(:user)

      RoleGrants.grant!(user, "patch_lead", scope: "ganymede", by: owner, reason: "spec")
      expect(slugs_for(user)).to include("patch-leads")
      expect(user.group_memberships.find_by!(group: group("patch-leads"))).to be_system

      RoleGrants.revoke!(user, "patch_lead", scope: "ganymede", by: owner, reason: "spec")
      expect(slugs_for(user)).not_to include("patch-leads")
    end

    it "is filled by sync_all for a lead whose role was written without RoleGrants" do
      user = create(:user)
      UserRole.create!(user:, role: Role.fetch!("patch_lead"), scope: "ganymede", granted_at: Time.current)
      expect(slugs_for(user)).not_to include("patch-leads")

      described_class.sync_all

      expect(slugs_for(user)).to include("patch-leads")
    end

    it "drops a lead whose program is no longer in the Knot settings" do
      user = create(:user)
      RoleGrants.grant!(user, "patch_lead", scope: "ganymede", by: owner, reason: "spec")
      allow(KnotSettings).to receive(:program_keys).and_return([])

      described_class.sync_all

      expect(slugs_for(user)).not_to include("patch-leads")
    end
  end

  it "leaves a membership that was added by hand" do
    user = create(:user)
    described_class.ensure_groups!
    manual = create(:group_membership, group: group("staff"), user: user, source: "manual")

    described_class.sync(user)

    expect(Group::Membership.exists?(manual.id)).to be(true)
  end

  describe ".sync_all" do
    it "repairs memberships that a callback-free change left wrong" do
      user = create(:user)
      # A role row written without RoleGrants (as raw SQL would), so no sync ran.
      UserRole.create!(user:, role: Role.fetch!("contractor"), granted_at: Time.current)
      expect(slugs_for(user)).to contain_exactly("everyone")

      described_class.sync_all

      expect(slugs_for(user)).to contain_exactly("everyone", "contractors")
    end
  end

  it "reserves the system slugs, so a manual group can't take one" do
    manual = build(:group, name: "Staff", slug: "staff")

    expect(manual).not_to be_valid
    expect(manual.errors[:slug]).to include("is reserved for a system group")
  end
end
