# frozen_string_literal: true

require "rails_helper"

# The Pundit policies for groups and access requests. ApplicationPolicy is
# fail-closed: a policy allows only what it names.
RSpec.describe "Access policies" do # rubocop:disable RSpec/DescribeClass
  let(:superadmin) { create(:user, :superadmin) }
  let(:group) { create(:group) }
  let(:manager_membership) { create(:group_membership, group:, user: create(:user), role: "manager") }
  let(:member_membership) { create(:group_membership, group:, user: create(:user)) }

  def manager = manager_membership.user

  def member = member_membership.user

  def outsider = @outsider ||= create(:user)

  describe ApplicationPolicy do
    it "refuses every action" do
      policy = described_class.new(superadmin, Object.new)

      expect(%i[index? show? create? new? update? edit? destroy?].map { |action| policy.public_send(action) }).to all(be(false))
      expect(described_class::Scope.new(superadmin, User.all).resolve).to be_empty
    end
  end

  describe GroupPolicy do
    before { [manager, member] }

    it "lets a manager or a superadmin manage a manual group" do
      expect(described_class.new(manager, group).manage?).to be(true)
      expect(described_class.new(superadmin, group).manage?).to be(true)
      expect(described_class.new(member, group).manage?).to be(false)
      expect(described_class.new(outsider, group).manage?).to be(false)
      expect(described_class.new(nil, group).manage?).to be(false)
    end

    it "lets nobody manage a system group by hand" do
      system_group = create(:group, :system, slug: "system-policy")

      expect(described_class.new(superadmin, system_group).manage?).to be(false)
    end

    it "scopes to the groups a user manages" do
      create(:group)

      expect(described_class::Scope.new(manager, Group.all).resolve).to contain_exactly(group)
      expect(described_class::Scope.new(member, Group.all).resolve).to be_empty
    end
  end

  describe Group::MembershipPolicy do
    it "lets a manager remove plain members only" do
      expect(described_class.new(manager, member_membership).destroy?).to be(true)
      expect(described_class.new(manager, manager_membership).destroy?).to be(false)
      expect(described_class.new(member, member_membership).destroy?).to be(false)
    end

    it "lets a superadmin remove anyone and change roles" do
      expect(described_class.new(superadmin, manager_membership).destroy?).to be(true)
      expect(described_class.new(superadmin, member_membership).update_role?).to be(true)
      expect(described_class.new(manager, member_membership).update_role?).to be(false)
    end
  end

  describe AccessRequestPolicy do
    def application = @application ||= Doorkeeper::Application.create!(name: "App", redirect_uri: "https://app.example.com/cb")

    def access_request = @access_request ||= AccessRequest.create!(user: outsider, application:, group:, reason: "Please")

    before { [manager, member] }

    it "lets a member ask only for themselves" do
      expect(described_class.new(outsider, AccessRequest.new(user: outsider)).create?).to be(true)
      expect(described_class.new(outsider, AccessRequest.new(user: member)).create?).to be(false)
    end

    it "lets a manager or a superadmin decide a pending request" do
      expect(described_class.new(manager, access_request).approve?).to be(true)
      expect(described_class.new(superadmin, access_request).deny?).to be(true)
      expect(described_class.new(member, access_request).approve?).to be(false)
      expect(described_class.new(outsider, access_request).approve?).to be(false)
    end

    it "lets nobody decide a request twice" do
      access_request.update!(status: "denied")

      expect(described_class.new(manager, access_request).approve?).to be(false)
    end

    it "scopes to the requests a user may decide" do
      access_request
      other = AccessRequest.create!(user: member, application:, group: create(:group), reason: "Please")

      expect(described_class::Scope.new(manager, AccessRequest.all).resolve).to contain_exactly(access_request)
      expect(described_class::Scope.new(superadmin, AccessRequest.all).resolve).to contain_exactly(access_request, other)
      expect(described_class::Scope.new(outsider, AccessRequest.all).resolve).to be_empty
    end
  end
end
