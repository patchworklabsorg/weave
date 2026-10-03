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

      expect(slugs_for(user)).to contain_exactly("staff", "board", "admins")
      expect(user.group_memberships).to all(be_system)
    end

    it "puts a plain member in no system group" do
      expect(slugs_for(create(:user))).to be_empty
    end

    {
      "staff"         => { is_staff: true },
      "board"         => { is_board: true },
      "contractors"   => { is_contractor: true },
      "admins"        => { role: :superadmin },
      "slack-members" => { slack_membership: "member" }
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
      user.update_column(:is_contractor, true) # rubocop:disable Rails/SkipsModelValidations
      expect(slugs_for(user)).to be_empty

      described_class.sync_all

      expect(slugs_for(user)).to contain_exactly("contractors")
    end
  end

  it "reserves the system slugs, so a manual group can't take one" do
    manual = build(:group, name: "Staff", slug: "staff")

    expect(manual).not_to be_valid
    expect(manual.errors[:slug]).to include("is reserved for a system group")
  end
end
