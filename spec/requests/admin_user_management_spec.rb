# frozen_string_literal: true

require "rails_helper"

# What each admin tier may do to which users through /admin/users. Roles rank
# user < admin < superadmin < owner; see UserAdminPermissions for the rules.
#
# Before these rules, any admin could edit anyone: change an owner's email to
# an address they control, request a magic link for it, and sign in as the
# owner. Role changes were rank-checked but silently dropped when refused.
RSpec.describe "Admin user management permissions", type: :request do
  let(:admin) { create(:user, :admin, :verified) }
  let(:superadmin) { create(:user, :superadmin, :verified) }
  let(:owner) { create(:user, :owner, :verified) }
  let(:member) { create(:user, :verified) }

  def update_user(user, **attrs)
    patch admin_user_path(user), params: { user: attrs }
  end

  def role_options
    select = response.body[/<select[^>]*name="user\[role\]".*?<\/select>/m]
    select.to_s.scan(/value="([^"]+)"/).flatten
  end

  describe "who an admin may manage" do
    context "when signed in as a plain admin" do
      before { sign_in_via_magic_link(admin) }

      it "can't change an owner's email, which would let them sign in as the owner by magic link" do
        update_user(owner, email: "attacker@example.com")

        expect(response).to redirect_to(admin_users_path)
        expect(owner.reload.email).not_to eq("attacker@example.com")
        expect(User.find_for_any_email("attacker@example.com")).to be_nil
      end

      it "can't edit a superadmin or a peer admin" do
        peer = create(:user, :admin, :verified)

        [superadmin, peer].each do |target|
          update_user(target, first_name: "Changed")

          expect(response).to redirect_to(admin_users_path)
          expect(target.reload.first_name).not_to eq("Changed")
        end
      end

      it "can't open the profile or edit form of someone above them" do
        get admin_user_path(owner)
        expect(response).to redirect_to(admin_users_path)

        get edit_admin_user_path(owner)
        expect(response).to redirect_to(admin_users_path)
      end

      it "can't delete an owner" do
        delete admin_user_path(owner)

        expect(response).to redirect_to(admin_users_path)
        expect(User.exists?(owner.id)).to be(true)
      end

      it "can still edit a member's details" do
        update_user(member, first_name: "Renamed", email: "renamed@example.com", is_staff: "1")

        expect(response).to redirect_to(admin_user_path(member))
        expect(member.reload).to have_attributes(first_name: "Renamed", email: "renamed@example.com", is_staff: true)
      end

      it "can still edit their own details" do
        update_user(admin, first_name: "Myself")

        expect(response).to redirect_to(admin_user_path(admin))
        expect(admin.reload.first_name).to eq("Myself")
      end
    end

    it "keeps a superadmin away from owners and other superadmins" do
      other_superadmin = create(:user, :superadmin, :verified)
      sign_in_via_magic_link(superadmin)

      [owner, other_superadmin].each do |target|
        update_user(target, email: "taken-over@example.com")

        expect(response).to redirect_to(admin_users_path)
        expect(target.reload.email).not_to eq("taken-over@example.com")
      end
    end

    it "keeps an owner from editing another owner, while still letting them view them" do
      other_owner = create(:user, :owner, :verified)
      sign_in_via_magic_link(owner)

      update_user(other_owner, email: "taken-over@example.com")
      expect(response).to redirect_to(admin_users_path)
      expect(other_owner.reload.email).not_to eq("taken-over@example.com")

      get admin_user_path(other_owner)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(edit_admin_user_path(other_owner))
    end

    # The p_id is the OIDC `sub` every client keys the account on, so regenerating it detaches the
    # user from all of them. It gets the same reach as editing.
    it "keeps a superadmin from regenerating an owner's p_id" do
      sign_in_via_magic_link(superadmin)
      original = owner.p_id

      patch regen_pid_admin_user_path(owner)

      expect(response).to redirect_to(admin_users_path)
      expect(owner.reload.p_id).to eq(original)
    end

    it "lets an owner regenerate a lower user's p_id" do
      sign_in_via_magic_link(owner)
      original = member.p_id

      patch regen_pid_admin_user_path(member)

      expect(member.reload.p_id).not_to eq(original)
    end
  end

  describe "role changes" do
    context "when signed in as a plain admin" do
      before { sign_in_via_magic_link(admin) }

      it "rejects a role change on a member, without applying the rest of the request" do
        update_user(member, first_name: "Renamed", role: "admin")

        expect(response).to have_http_status(:unprocessable_content)
        expect(member.reload).to have_attributes(role: "user", first_name: "John")
      end

      it "rejects a change to their own role" do
        update_user(admin, role: "owner")

        expect(response).to have_http_status(:unprocessable_content)
        expect(admin.reload.role).to eq("admin")
      end

      it "accepts a submission that repeats the member's current role" do
        update_user(member, first_name: "Renamed", role: "user")

        expect(response).to redirect_to(admin_user_path(member))
        expect(member.reload).to have_attributes(role: "user", first_name: "Renamed")
      end
    end

    context "when signed in as a superadmin" do
      before { sign_in_via_magic_link(superadmin) }

      it "can promote a member to admin and demote an admin to member" do
        update_user(member, role: "admin")
        expect(response).to redirect_to(admin_user_path(member))
        expect(member.reload.role).to eq("admin")

        update_user(admin, role: "user")
        expect(response).to redirect_to(admin_user_path(admin))
        expect(admin.reload.role).to eq("user")
      end

      it "can't grant their own role or one above it" do
        %w[superadmin owner].each do |role|
          update_user(member, role: role)

          expect(response).to have_http_status(:unprocessable_content)
          expect(member.reload.role).to eq("user")
        end
      end

      it "can't change their own role" do
        update_user(superadmin, role: "owner")

        expect(response).to have_http_status(:unprocessable_content)
        expect(superadmin.reload.role).to eq("superadmin")
      end
    end

    context "when signed in as an owner" do
      before { sign_in_via_magic_link(owner) }

      it "can grant any role, including superadmin and owner" do
        update_user(member, role: "superadmin")
        expect(member.reload.role).to eq("superadmin")

        update_user(member, role: "owner")
        expect(member.reload.role).to eq("owner")
      end

      it "can't change their own role" do
        update_user(owner, role: "user")

        expect(response).to have_http_status(:unprocessable_content)
        expect(owner.reload.role).to eq("owner")
      end

      it "rejects role values that aren't role names" do
        ["3", "", "bogus"].each do |role|
          update_user(member, role: role)

          expect(response).to have_http_status(:unprocessable_content)
          expect(member.reload.role).to eq("user")
        end
      end
    end
  end

  describe "password resets" do
    let(:new_password) { "BrandNewSecret123!" }

    it "lets a superadmin reset the password of an admin below them" do
      sign_in_via_magic_link(superadmin)

      update_user(admin, password: new_password, password_confirmation: new_password)

      expect(response).to redirect_to(admin_user_path(admin))
      expect(admin.reload.authenticate(new_password)).to be_truthy
    end

    it "rejects a password reset from a plain admin" do
      sign_in_via_magic_link(admin)

      update_user(member, password: new_password, password_confirmation: new_password)

      expect(response).to have_http_status(:unprocessable_content)
      expect(member.reload.authenticate(new_password)).to be(false)
    end

    it "rejects a superadmin resetting their own password here" do
      sign_in_via_magic_link(superadmin)

      update_user(superadmin, password: new_password, password_confirmation: new_password)

      expect(response).to have_http_status(:unprocessable_content)
      expect(superadmin.reload.authenticate(new_password)).to be(false)
    end

    it "ignores the blank password fields the edit form always submits" do
      sign_in_via_magic_link(superadmin)

      update_user(member, first_name: "Renamed", password: "", password_confirmation: "")

      expect(response).to redirect_to(admin_user_path(member))
      expect(member.reload.first_name).to eq("Renamed")
    end
  end

  describe "the edit form" do
    it "shows a plain admin the access level read-only and no password fields" do
      sign_in_via_magic_link(admin)

      get edit_admin_user_path(member)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('name="user[role]"', 'name="user[password]"')
      expect(response.body).to include("Only a superadmin or owner who outranks this user")
    end

    it "offers a superadmin only the roles below their own" do
      sign_in_via_magic_link(superadmin)

      get edit_admin_user_path(member)

      expect(role_options).to eq(%w[user admin])
      expect(response.body).to include('name="user[password]"')
    end

    it "offers an owner every role" do
      sign_in_via_magic_link(owner)

      get edit_admin_user_path(member)

      expect(role_options).to eq(%w[user admin superadmin owner])
    end

    it "offers no role choice on your own account" do
      sign_in_via_magic_link(owner)

      get edit_admin_user_path(owner)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('name="user[role]"')
    end
  end
end
