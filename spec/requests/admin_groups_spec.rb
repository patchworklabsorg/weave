# frozen_string_literal: true

require "rails_helper"

# Groups will grant access to OAuth apps, so a change to a group is a change to
# who can use which app. Any admin may look; only a superadmin may change.
RSpec.describe "Admin groups", type: :request do
  let(:admin) { create(:user, :admin, :verified) }
  let(:superadmin) { create(:user, :superadmin, :verified) }
  let(:member) { create(:user, :verified) }
  let!(:group) { create(:group, name: "Engineering", slug: "eng") }

  context "when signed in as a plain admin" do
    before { sign_in_via_magic_link(admin) }

    it "can list and view groups" do
      create(:group_membership, group: group, user: member)

      get admin_groups_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Engineering")

      get admin_group_path(group)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(member.email)
      expect(response.body).not_to include("Add Member")
    end

    it "can't create, edit or delete a group" do
      post admin_groups_path, params: { group: { name: "Sneaky" } }
      expect(response).to redirect_to(admin_groups_path)
      expect(Group.exists?(name: "Sneaky")).to be(false)

      patch admin_group_path(group), params: { group: { name: "Renamed" } }
      expect(group.reload.name).to eq("Engineering")

      delete admin_group_path(group)
      expect(group.reload.deleted_at).to be_nil
    end

    it "can't add themselves or anyone else to a group" do
      post admin_group_memberships_path(group), params: { group_membership: { email: admin.email } }

      expect(response).to redirect_to(admin_groups_path)
      expect(group.users).to be_empty
    end

    it "can't remove a member" do
      membership = create(:group_membership, group: group, user: member)

      delete admin_group_membership_path(group, membership)

      expect(Group::Membership.exists?(membership.id)).to be(true)
    end
  end

  context "when signed in as a superadmin" do
    before { sign_in_via_magic_link(superadmin) }

    it "creates a group and records who created it" do
      post admin_groups_path, params: { group: { name: "Design Team", description: "Designers" } }

      created = Group.find_by!(slug: "design-team")
      expect(response).to redirect_to(admin_group_path(created))
      expect(created.created_by).to eq(superadmin)
      expect(created).to be_manual
    end

    it "can't create a system group through the form" do
      post admin_groups_path, params: { group: { name: "Fake Staff", kind: "system" } }

      expect(Group.find_by!(slug: "fake-staff")).to be_manual
    end

    it "renames a group but keeps its slug" do
      patch admin_group_path(group), params: { group: { name: "Engineers", slug: "changed" } }

      expect(group.reload.name).to eq("Engineers")
      expect(group.slug).to eq("eng")
    end

    it "shows the form again when the input is not valid" do
      post admin_groups_path, params: { group: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "soft-deletes a group" do
      delete admin_group_path(group)

      expect(response).to redirect_to(admin_groups_path)
      expect(Group.with_deleted.find(group.id).deleted_at).to be_present
    end

    it "adds a member by email, with who added them and an optional expiry" do
      expires = 1.week.from_now.change(sec: 0)

      post admin_group_memberships_path(group),
           params: { group_membership: { email: member.email.upcase, expires_at: expires.strftime("%Y-%m-%dT%H:%M") } }

      membership = group.memberships.sole
      expect(response).to redirect_to(admin_group_path(group))
      expect(membership.user).to eq(member)
      expect(membership.added_by).to eq(superadmin)
      expect(membership.expires_at).to be_within(1.minute).of(expires)
    end

    it "says so when no user has the email" do
      post admin_group_memberships_path(group), params: { group_membership: { email: "nobody@example.com" } }

      expect(response).to redirect_to(admin_group_path(group))
      expect(flash[:alert]).to eq("No user has that email address.")
    end

    it "does not add the same person twice" do
      create(:group_membership, group: group, user: member)

      post admin_group_memberships_path(group), params: { group_membership: { email: member.email } }

      expect(flash[:alert]).to include("already in this group")
      expect(group.memberships.count).to eq(1)
    end

    it "removes a member" do
      membership = create(:group_membership, group: group, user: member)

      delete admin_group_membership_path(group, membership)

      expect(response).to redirect_to(admin_group_path(group))
      expect(Group::Membership.exists?(membership.id)).to be(false)
    end

    it "shows the user's groups on their admin page" do
      create(:group_membership, group: group, user: member)

      get admin_user_path(member)

      expect(response.body).to include("Engineering")
    end

    context "with a system group" do
      let!(:system_group) { create(:group, :system, name: "Staff", slug: "staff") }

      it "refuses hand edits, deletion and member changes" do
        patch admin_group_path(system_group), params: { group: { name: "Renamed" } }
        expect(response).to redirect_to(admin_group_path(system_group))
        expect(system_group.reload.name).to eq("Staff")

        delete admin_group_path(system_group)
        expect(system_group.reload.deleted_at).to be_nil

        post admin_group_memberships_path(system_group), params: { group_membership: { email: member.email } }
        expect(system_group.memberships).to be_empty
      end
    end
  end
end
