# frozen_string_literal: true

require "rails_helper"

# A group that holds a patch role gives that role to every member, and a patch
# role can open a patch's finances in Quilt. So only a superadmin adds a member
# to such a group, through every path. Removing a member stays as before.
RSpec.describe "Groups that hold patch roles", type: :request do
  include ActiveJob::TestHelper

  let(:manager) { create(:user, :verified, :accepted_code_of_conduct) }
  let(:member) { create(:user, :verified, :accepted_code_of_conduct) }
  let(:superadmin) { create(:user, :superadmin, :verified) }
  let(:group) { create(:group, name: "Finance", slug: "finance") }

  before do
    create(:group_membership, group:, user: manager, role: "manager")
    ganymede = create(:patch, slug: "ganymede", name: "Project Ganymede")
    PatchRoleAssignment.create!(role: ganymede.roles.create!(key: "quilt:viewer", name: "Quilt viewer"), assignee: group)
  end

  it "refuses a member that a group manager adds, and says why on the group page" do
    sign_in_via_magic_link(manager)

    get group_path(group)
    expect(response.body).to include("This group holds patch roles, so only a superadmin adds members.")
    expect(response.body).not_to include("Add a member by email")

    post group_members_path(group), params: { group_membership: { email: member.email } }

    expect(group.users).not_to include(member)
    expect(PatchRoles.for(member)).to eq({})
  end

  it "lets a manager still remove a member" do
    membership = create(:group_membership, group:, user: member, added_by: superadmin)
    sign_in_via_magic_link(manager)

    delete group_member_path(group, membership)

    expect(Group::Membership.exists?(membership.id)).to be(false)
  end

  describe "an access request for an app whose request group holds a patch role" do
    let(:request_record) do
      application = Doorkeeper::Application.create!(name: "Krater", redirect_uri: "https://krater.example.com/cb",
                                                    scopes: "openid profile", access_policy: "restricted")
      ApplicationAccessGrant.create!(application:, grantee: group)
      application.update!(access_request_group: group)
      AccessRequest.create!(user: member, application:, group:, reason: "Please")
    end

    it "is not approved by a manager, and adds nobody" do
      sign_in_via_magic_link(manager)

      patch approve_access_request_path(request_record)

      expect(flash[:alert]).to include("Only a superadmin can approve this request")
      expect(request_record.reload).to be_pending
      expect(group.users).not_to include(member)
      expect(PatchRoles.for(member)).to eq({})
    end

    it "is approved by a superadmin" do
      AccessRequests.approve!(request_record, by: superadmin)

      expect(group.users).to include(member)
      expect(PatchRoles.for(member)).to eq("ganymede" => ["quilt:viewer"])
    end
  end

  it "lets a superadmin add a member in the admin panel" do
    sign_in_via_magic_link(superadmin)

    get admin_group_path(group)
    expect(response.body).to include("This group holds patch roles, so only a superadmin adds members.")

    post admin_group_memberships_path(group), params: { group_membership: { email: member.email } }

    expect(group.users).to include(member)
    expect(PatchRoles.for(member)).to eq("ganymede" => ["quilt:viewer"])
  end

  it "refuses a new member that no superadmin added, at the model, and an expired member who starts again" do
    expect(group.memberships.build(user: member).save).to be(false)
    expect(group.memberships.build(user: member, added_by: manager).save).to be(false)

    expired = create(:group_membership, group:, user: create(:user, :verified), added_by: superadmin)
    expired.update_column(:expires_at, 1.day.ago) # rubocop:disable Rails/SkipsModelValidations
    expect(expired.update(expires_at: nil, added_by: manager)).to be(false)
    expect(expired.update(expires_at: nil, added_by: superadmin)).to be(true)
  end
end
