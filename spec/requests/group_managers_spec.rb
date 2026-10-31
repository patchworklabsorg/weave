# frozen_string_literal: true

require "rails_helper"

# A group manager adds and removes members outside the admin panel (see
# GroupPolicy and Group::MembershipPolicy). Only a superadmin makes managers.
RSpec.describe "Group managers", type: :request do
  let(:manager) { create(:user, :verified) }
  let(:member) { create(:user, :verified) }
  let(:group) { create(:group, name: "Reviewers", slug: "reviewers") }

  before { create(:group_membership, group:, user: manager, role: "manager") }

  context "when signed in as a manager" do
    before { sign_in_via_magic_link(manager) }

    it "lists the groups they manage" do
      create(:group, name: "Other Group")

      get groups_path

      expect(response.body).to include("Reviewers")
      expect(response.body).not_to include("Other Group")
    end

    it "adds a member" do
      post group_members_path(group), params: { group_membership: { email: member.email } }

      expect(response).to redirect_to(group_path(group))
      expect(group.memberships.find_by(user: member)).to have_attributes(role: "member", added_by: manager)
    end

    it "removes a member" do
      membership = create(:group_membership, group:, user: member)

      delete group_member_path(group, membership)

      expect(Group::Membership.exists?(membership.id)).to be(false)
    end

    it "can't remove another manager" do
      other = create(:group_membership, group:, user: member, role: "manager")

      delete group_member_path(group, other)

      expect(response).to redirect_to(profile_path)
      expect(Group::Membership.exists?(other.id)).to be(true)
    end

    it "can't add members to a sponsored project group" do
      group.update!(waives_code_of_conduct: true)

      post group_members_path(group), params: { group_membership: { email: member.email } }

      expect(response).to redirect_to(profile_path)
      expect(group.users).not_to include(member)
    end

    it "can't manage a group they don't manage" do
      other_group = create(:group)

      get group_path(other_group)
      expect(response).to redirect_to(profile_path)

      post group_members_path(other_group), params: { group_membership: { email: member.email } }
      expect(other_group.users).to be_empty
    end
  end

  it "keeps plain members out" do
    create(:group_membership, group:, user: member)
    sign_in_via_magic_link(member)

    get group_path(group)
    expect(response).to redirect_to(profile_path)

    post group_members_path(group), params: { group_membership: { email: create(:user).email } }
    expect(group.memberships.count).to eq(2)
  end

  it "stops being a manager when the membership expires" do
    Group::Membership.find_by(user: manager).update_column(:expires_at, 1.minute.ago) # rubocop:disable Rails/SkipsModelValidations
    sign_in_via_magic_link(manager)

    get group_path(group)

    expect(response).to redirect_to(profile_path)
  end

  describe "making managers in the admin panel" do
    let!(:membership) { create(:group_membership, group:, user: member) }

    it "is open to a superadmin" do
      sign_in_via_magic_link(create(:user, :superadmin, :verified))

      patch role_admin_group_membership_path(group, membership), params: { role: "manager" }

      expect(membership.reload).to be_role_manager
      expect(group.managed_by?(member)).to be(true)
    end

    it "is closed to a plain admin" do
      sign_in_via_magic_link(create(:user, :admin, :verified))

      patch role_admin_group_membership_path(group, membership), params: { role: "manager" }

      expect(membership.reload).to be_role_member
    end

    it "refuses a system group" do
      system_group = create(:group, :system, slug: "system-test")
      system_membership = create(:group_membership, group: system_group, user: member, source: "system")
      sign_in_via_magic_link(create(:user, :superadmin, :verified))

      patch role_admin_group_membership_path(system_group, system_membership), params: { role: "manager" }

      expect(system_membership.reload).to be_role_member
    end
  end
end
