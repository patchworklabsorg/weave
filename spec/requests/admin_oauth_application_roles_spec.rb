# frozen_string_literal: true

require "rails_helper"

# App roles are sent to the app and give access to it, so only a superadmin
# may change them. Plain admins can see them.
RSpec.describe "Admin OAuth application roles", type: :request do
  let(:admin) { create(:user, :admin, :verified) }
  let(:superadmin) { create(:user, :superadmin, :verified) }
  let(:member) { create(:user, :verified) }
  let(:application) { Doorkeeper::Application.create!(name: "Krater", redirect_uri: "https://krater.example.com/cb") }
  let(:role) { ApplicationRole.create!(application: application, key: "reviewer", name: "Reviewer") }

  context "when signed in as a plain admin" do
    before { sign_in_via_magic_link(admin) }

    it "can see roles but not the forms" do
      ApplicationRoleAssignment.create!(role: role, assignee: member)

      get admin_oauth_application_path(application)

      expect(response.body).to include("Reviewer", "reviewer", member.full_name)
      expect(response.body).not_to include("Add role")
    end

    it "can't add a role or an assignment" do
      post admin_oauth_application_roles_path(application), params: { role: { key: "admin", name: "Admin" } }
      post admin_oauth_application_role_assignments_path(application, role), params: { assignment: { email: admin.email } }

      expect(ApplicationRole.pluck(:key)).to eq(["reviewer"])
      expect(ApplicationRoleAssignment.count).to eq(0)
    end

    it "can't delete a role" do
      delete admin_oauth_application_role_path(application, role)

      expect(ApplicationRole.exists?(role.id)).to be(true)
    end
  end

  context "when signed in as a superadmin" do
    before { sign_in_via_magic_link(superadmin) }

    it "adds a role" do
      post admin_oauth_application_roles_path(application), params: { role: { key: "admin", name: "Admin", description: "Runs Krater" } }

      expect(ApplicationRole.find_by!(application: application, key: "admin")).to have_attributes(name: "Admin", created_by: superadmin)
      expect(response).to redirect_to(admin_oauth_application_path(application, anchor: "roles"))
    end

    it "shows the error for a bad key" do
      post admin_oauth_application_roles_path(application), params: { role: { key: "Bad Key", name: "Bad" } }

      expect(ApplicationRole.count).to eq(0)
      expect(flash[:alert]).to include("Key")
    end

    it "gives a role to a user by email and to a group" do
      group = create(:group, name: "Krater Reviewers")
      post admin_oauth_application_role_assignments_path(application, role), params: { assignment: { email: member.email } }
      post admin_oauth_application_role_assignments_path(application, role), params: { assignment: { group_id: group.id } }

      expect(role.assignments.map(&:assignee)).to contain_exactly(member, group)
    end

    it "says so when no user has the email" do
      post admin_oauth_application_role_assignments_path(application, role), params: { assignment: { email: "nobody@example.com" } }

      expect(flash[:alert]).to eq("No user has that email address.")
    end

    it "removes an assignment and revokes lost access" do
      assignment = ApplicationRoleAssignment.create!(role: role, assignee: member)

      expect { delete admin_oauth_application_role_assignment_path(application, role, assignment) }
        .to have_enqueued_job(RevokeLostAppAccessJob).with(application_id: application.id)
      expect(ApplicationRoleAssignment.exists?(assignment.id)).to be(false)
    end

    it "deletes a role with its assignments" do
      ApplicationRoleAssignment.create!(role: role, assignee: member)

      delete admin_oauth_application_role_path(application, role)

      expect(ApplicationRole.count).to eq(0)
      expect(ApplicationRoleAssignment.count).to eq(0)
    end

    it "does not touch a role of another app" do
      other = Doorkeeper::Application.create!(name: "Other", redirect_uri: "https://other.example.com/cb")

      delete admin_oauth_application_role_path(other, role)

      expect(response).to have_http_status(:not_found)
      expect(ApplicationRole.exists?(role.id)).to be(true)
    end

    it "shows the user's roles on the admin user page" do
      ApplicationRoleAssignment.create!(role: role, assignee: member)

      get admin_user_path(member)

      expect(response.body).to include("App Roles", "Krater", "reviewer")
    end
  end
end
