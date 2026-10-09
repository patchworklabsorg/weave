# frozen_string_literal: true

require "rails_helper"

# Who can use an app is decided by its access policy and grants. Changing
# either is a grant of access, so only a superadmin may do it.
RSpec.describe "Admin OAuth application access", type: :request do
  let(:admin) { create(:user, :admin, :verified) }
  let(:superadmin) { create(:user, :superadmin, :verified) }
  let(:member) { create(:user, :verified, :accepted_code_of_conduct) }
  let(:group) { create(:group, name: "Engineering") }
  let(:application) { Doorkeeper::Application.create!(name: "Wiki", redirect_uri: "https://wiki.example.com/cb") }

  context "when signed in as a plain admin" do
    before { sign_in_via_magic_link(admin) }

    it "can see the access panel but not change the policy" do
      get admin_oauth_application_path(application)
      expect(response.body).to include("Everyone who can sign in to Weave can use this app.")
      expect(response.body).not_to include("Restrict access")

      patch access_policy_admin_oauth_application_path(application), params: { access_policy: "restricted" }

      expect(application.reload.access_policy).to eq("everyone")
    end

    it "can't add or remove grants" do
      post admin_oauth_application_access_grants_path(application), params: { access_grant: { email: admin.email } }
      expect(ApplicationAccessGrant.count).to eq(0)

      grant = ApplicationAccessGrant.create!(application: application, grantee: member)
      delete admin_oauth_application_access_grant_path(application, grant)
      expect(ApplicationAccessGrant.exists?(grant.id)).to be(true)
    end
  end

  context "when signed in as a superadmin" do
    before { sign_in_via_magic_link(superadmin) }

    it "restricts an app and opens it again" do
      patch access_policy_admin_oauth_application_path(application), params: { access_policy: "restricted" }
      expect(application.reload.access_policy).to eq("restricted")

      patch access_policy_admin_oauth_application_path(application), params: { access_policy: "everyone" }
      expect(application.reload.access_policy).to eq("everyone")
    end

    it "revokes tokens of users without a grant when an app is restricted" do
      expect { patch access_policy_admin_oauth_application_path(application), params: { access_policy: "restricted" } }
        .to have_enqueued_job(RevokeLostAppAccessJob).with(application_id: application.id)
    end

    it "does not revoke anything when an app is opened to everyone" do
      application.update!(access_policy: "restricted")

      expect { patch access_policy_admin_oauth_application_path(application), params: { access_policy: "everyone" } }
        .not_to have_enqueued_job(RevokeLostAppAccessJob)
    end

    it "refuses an unknown policy" do
      patch access_policy_admin_oauth_application_path(application), params: { access_policy: "admins-only" }

      expect(flash[:alert]).to eq("Unknown access policy.")
      expect(application.reload.access_policy).to eq("everyone")
    end

    it "grants a group and a user, and records who did it" do
      post admin_oauth_application_access_grants_path(application), params: { access_grant: { group_id: group.id } }
      post admin_oauth_application_access_grants_path(application), params: { access_grant: { email: member.email } }

      grants = ApplicationAccessGrant.for_application(application)
      expect(grants.map(&:grantee)).to contain_exactly(group, member)
      expect(grants.map(&:created_by).uniq).to eq([superadmin])
    end

    it "does not grant the same group twice" do
      ApplicationAccessGrant.create!(application: application, grantee: group)

      post admin_oauth_application_access_grants_path(application), params: { access_grant: { group_id: group.id } }

      expect(flash[:alert]).to include("already has access")
    end

    it "says so when no user has the email" do
      post admin_oauth_application_access_grants_path(application), params: { access_grant: { email: "nobody@example.com" } }

      expect(flash[:alert]).to eq("No user has that email address.")
    end

    it "removes a grant" do
      grant = ApplicationAccessGrant.create!(application: application, grantee: group)

      delete admin_oauth_application_access_grant_path(application, grant)

      expect(ApplicationAccessGrant.exists?(grant.id)).to be(false)
    end

    it "shows the grants on the app page" do
      application.update!(access_policy: "restricted")
      ApplicationAccessGrant.create!(application: application, grantee: group)

      get admin_oauth_application_path(application)

      expect(response.body).to include("Only the users and groups below can use this app.", "Engineering", "Open to everyone")
    end

    it "explains on the user page why the user can or can't use each restricted app" do
      application.update!(access_policy: "restricted")
      create(:group_membership, group: group, user: member)
      ApplicationAccessGrant.create!(application: application, grantee: group)
      Doorkeeper::Application.create!(name: "Payroll", redirect_uri: "https://payroll.example.com/cb", access_policy: "restricted")

      get admin_user_path(member)

      expect(response.body).to include("Wiki", "Member of Engineering", "Payroll", "No grant for this user or their groups")
    end
  end

  describe "the code-of-conduct requirement" do
    it "lets a superadmin opt an app out and back in" do
      sign_in_via_magic_link(superadmin)

      patch code_of_conduct_admin_oauth_application_path(application), params: { required: false }
      expect(application.reload.requires_code_of_conduct).to be(false)

      expect { patch code_of_conduct_admin_oauth_application_path(application), params: { required: true } }
        .to have_enqueued_job(RevokeLostAppAccessJob).with(application_id: application.id)
      expect(application.reload.requires_code_of_conduct).to be(true)
    end

    it "does not let a plain admin change it" do
      sign_in_via_magic_link(admin)

      patch code_of_conduct_admin_oauth_application_path(application), params: { required: false }

      expect(application.reload.requires_code_of_conduct).to be(true)
    end
  end

  describe "the code-of-conduct exemption for one user" do
    it "lets a superadmin exempt a user and take the exemption away" do
      sign_in_via_magic_link(superadmin)

      patch code_of_conduct_exemption_admin_user_path(member), params: { exempt: true }
      expect(member.reload.code_of_conduct_exempt).to be(true)

      expect { patch code_of_conduct_exemption_admin_user_path(member), params: { exempt: false } }
        .to have_enqueued_job(RevokeLostAppAccessJob).with(user_id: member.id)
      expect(member.reload.code_of_conduct_exempt).to be(false)
    end

    it "does not let a plain admin change it" do
      sign_in_via_magic_link(admin)

      patch code_of_conduct_exemption_admin_user_path(member), params: { exempt: true }

      expect(member.reload.code_of_conduct_exempt).to be(false)
    end
  end
end
