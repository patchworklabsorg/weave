# frozen_string_literal: true

require "rails_helper"

# The roles a patch defines, and who holds them. A role can open a patch's
# finances in Quilt, so only a superadmin changes them. Any admin can look.
RSpec.describe "Admin patch roles", type: :request do
  let(:admin) { create(:user, :admin, :verified) }
  let(:superadmin) { create(:user, :superadmin, :verified) }
  let(:member) { create(:user, :verified, email: "member@example.com") }
  let!(:ganymede) { create(:patch, slug: "ganymede", name: "Project Ganymede") }
  let(:group) { create(:group, name: "Finance") }

  def role(key = "viewer") = ganymede.roles.find_or_create_by!(key:) { |record| record.name = key.titleize }

  context "when signed in as a superadmin" do
    before { sign_in_via_magic_link(superadmin) }

    it "adds a role, renames it and deletes it" do
      get admin_patch_path(ganymede)
      expect(response.body).to include("Add role")

      post admin_patch_roles_path(ganymede), params: { role: { key: "viewer", name: "Viewer", description: "Reads finances." } }
      added = ganymede.roles.find_by!(key: "viewer")
      expect(added).to have_attributes(name: "Viewer", description: "Reads finances.", created_by: superadmin)
      expect(response).to redirect_to(admin_patch_path(ganymede, anchor: "roles"))

      patch admin_patch_role_path(ganymede, added), params: { role: { name: "Finance viewer", description: "", key: "reader" } }
      expect(added.reload).to have_attributes(name: "Finance viewer", description: "", key: "viewer")

      delete admin_patch_role_path(ganymede, added)
      expect(ganymede.roles.reload).to be_empty
    end

    it "refuses the reserved key lead and a bad key" do
      post admin_patch_roles_path(ganymede), params: { role: { key: "lead", name: "Lead" } }
      expect(flash[:alert]).to include("reserved for the patch lead")

      post admin_patch_roles_path(ganymede), params: { role: { key: "Bad Key", name: "Bad" } }
      expect(ganymede.roles.reload).to be_empty
    end

    it "gives a role to a user and a group, and takes it away" do
      post admin_patch_role_assignments_path(ganymede, role), params: { assignment: { email: member.email } }
      post admin_patch_role_assignments_path(ganymede, role), params: { assignment: { group_id: group.public_id } }

      expect(role.assignments.map(&:assignee)).to contain_exactly(member, group)
      expect(PatchRoles.for(member)).to eq("ganymede" => ["viewer"])

      assignment = role.assignments.find_by!(assignee: member)
      delete admin_patch_role_assignment_path(ganymede, role, assignment)
      expect(role.assignments.reload.map(&:assignee)).to eq([group])
      expect(PatchRoles.for(member)).to eq({})
    end

    it "says when the user or the group does not exist" do
      post admin_patch_role_assignments_path(ganymede, role), params: { assignment: { email: "nobody@example.com" } }
      expect(flash[:alert]).to eq("No user has that email address.")

      post admin_patch_role_assignments_path(ganymede, role), params: { assignment: { group_id: "grp_nothing" } }
      expect(flash[:alert]).to eq("That group doesn't exist.")
      expect(role.assignments).to be_empty
    end

    it "finds a role only in its own patch" do
      other = create(:patch, slug: "europa").roles.create!(key: "viewer", name: "Viewer")

      delete admin_patch_role_path(ganymede, other)

      expect(response).to have_http_status(:not_found)
      expect(PatchRole.exists?(other.id)).to be(true)
    end
  end

  context "when signed in as a plain admin" do
    before { sign_in_via_magic_link(admin) }

    it "sees the roles and refuses every change" do
      assignment = PatchRoleAssignment.create!(role:, assignee: member)

      get admin_patch_path(ganymede)
      expect(response.body).to include("Viewer", member.full_name)
      expect(response.body).not_to include("Add role", "Delete role", "Give to a user")

      post admin_patch_roles_path(ganymede), params: { role: { key: "reviewer", name: "Reviewer" } }
      expect(response).to redirect_to(admin_patch_path(ganymede))
      patch admin_patch_role_path(ganymede, role), params: { role: { name: "Renamed" } }
      delete admin_patch_role_path(ganymede, role)
      post admin_patch_role_assignments_path(ganymede, role), params: { assignment: { email: admin.email } }
      delete admin_patch_role_assignment_path(ganymede, role, assignment)

      expect(ganymede.roles.reload.map(&:key)).to eq(["viewer"])
      expect(role.reload.name).to eq("Viewer")
      expect(role.assignments.map(&:assignee)).to eq([member])
    end
  end

  it "does not exist for a member" do
    sign_in_via_magic_link(member)

    post admin_patch_roles_path(ganymede), params: { role: { key: "reviewer", name: "Reviewer" } }
    expect(response).to have_http_status(:not_found)

    post admin_patch_role_assignments_path(ganymede, role), params: { assignment: { email: member.email } }
    expect(response).to have_http_status(:not_found)
    expect(role.assignments).to be_empty
  end
end
