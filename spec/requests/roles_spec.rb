# frozen_string_literal: true

require "rails_helper"

# The role pages: the roles section of the governance page, the staff and
# contractors page, and the patch lead proposal. Bullet raises on an N+1 in
# request specs, so these pages run with several holders of each role.
RSpec.describe "Roles pages", type: :request do
  let(:owner) { create(:user, :owner, :verified, first_name: "Olive") }

  describe "the roles section of the governance page" do
    it "lists each role, its holders with the scope, and its grant rule, with no N+1" do
      create_list(:user, 2, :key_holder)
      create(:user, :identity_lead, first_name: "Lena")
      create_list(:user, 2, :verified, is_board: true)
      create(:user, :verified, :patch_lead, first_name: "Adam")
      create_list(:user, 2, :verified, is_staff: true)
      sign_in_via_magic_link(owner)

      get identity_governance_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Roles", "Patch lead (scoped by program)", "Adam Doe (ganymede)",
                                       "Grant: An owner proposes. Every board member approves.",
                                       "Grant: Any admin, at once.", "Revoke: One owner or identity lead, at once.",
                                       "· key holder", "· lead")
    end

    it "lets an owner propose a patch lead for a program" do
      lead = create(:user, :verified)
      create(:verification, :verified, user: lead)
      sign_in_via_magic_link(owner)

      post identity_governance_proposals_path, params: { person: lead.p_id, kind: "add_patch_lead", scope: "ganymede", reason: "Leads it." }

      proposal = IdentityGovernanceProposal.sole
      expect(proposal).to have_attributes(kind: "add_patch_lead", scope: "ganymede", subject: lead)
      expect(response).to redirect_to(identity_governance_proposal_path(proposal))
    end
  end

  describe "the staff and contractors page" do
    it "lists the holders with no N+1, and only for an admin" do
      admin = create(:user, :admin, :verified)
      create_list(:user, 3, :verified, is_staff: true)
      create_list(:user, 2, :verified, is_contractor: true)

      sign_in_via_magic_link(create(:user, :verified))
      get admin_role_assignments_path
      expect(response).to redirect_to(login_path)

      sign_in_via_magic_link(admin)
      get admin_role_assignments_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Staff and contractors", "Revoke")
    end
  end

  describe "the roles section of the admin user page" do
    it "shows the roles of the user and the grant forms the actor may use" do
      user = create(:user, :verified, :patch_lead, is_staff: true)
      sign_in_via_magic_link(owner)

      get admin_user_path(user)

      expect(response.body).to include("Revoke staff", "Revoke patch lead (ganymede)", "Grant board member", "Grant contractor",
                                       "To grant it, an owner proposes the change on the identity governance page.")
    end
  end
end
