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

      it "can't delete anyone: deletion goes through a deletion request" do
        delete "/admin/users/#{owner.p_id}"

        expect(response).to have_http_status(:not_found)
        expect(User.exists?(owner.id)).to be(true)
      end

      it "can still edit a member's details" do
        update_user(member, first_name: "Renamed", email: "renamed@example.com")

        expect(response).to redirect_to(admin_user_path(member))
        expect(member.reload).to have_attributes(first_name: "Renamed", email: "renamed@example.com")
      end

      it "ignores the old role fields of the user form: roles change through the roles section" do
        update_user(member, first_name: "Renamed", is_staff: "1", is_board: "1", is_contractor: "1")

        expect(response).to redirect_to(admin_user_path(member))
        expect(member.reload).to have_attributes(first_name: "Renamed", is_staff: false, is_board: false, is_contractor: false)
        expect(UserRole.count).to eq(0)
      end

      it "can change a member's legal name" do
        update_user(member, legal_first_name: "Jonathan", legal_last_name: "Dorian")

        expect(member.reload).to have_attributes(legal_first_name: "Jonathan", legal_last_name: "Dorian")
      end

      it "can't change the legal name of a peer admin or someone above them" do
        peer = create(:user, :admin, :verified)

        [peer, superadmin, owner].each do |target|
          update_user(target, legal_first_name: "Changed", legal_last_name: "Changed")

          expect(response).to redirect_to(admin_users_path)
          expect(target.reload).to have_attributes(legal_first_name: nil, legal_last_name: nil)
        end
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

  describe "creating users" do
    let(:new_user_params) { { first_name: "New", last_name: "Person", email: "new.person@example.com" } }

    it "renders the new user form" do
      sign_in_via_magic_link(admin)

      get new_admin_user_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New user")
    end

    it "creates a user who signs in by magic link, with no password needed" do
      sign_in_via_magic_link(admin)

      expect { post admin_users_path, params: { user: new_user_params } }.to change(User, :count).by(1)

      created = User.find_by(email: "new.person@example.com")
      expect(response).to redirect_to(admin_users_path)
      expect(created).to be_user
    end

    it "re-renders the form when the user is invalid" do
      sign_in_via_magic_link(admin)

      post admin_users_path, params: { user: new_user_params.merge(first_name: "") }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("New user")
    end

    it "does not let a plain admin create an admin" do
      sign_in_via_magic_link(admin)

      expect { post admin_users_path, params: { user: new_user_params.merge(role: "admin") } }.not_to change(User, :count)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "lets an owner create an admin" do
      sign_in_via_magic_link(owner)

      post admin_users_path, params: { user: new_user_params.merge(role: "admin") }

      expect(User.find_by(email: "new.person@example.com")).to be_admin
    end
  end

  # Board membership drives identity team governance (see IdentityGovernance),
  # so only an owner changes it (the board rule in config/roles.yml), and each
  # change is logged and told to the board. It changes through the roles
  # section of the edit page (Admin::RoleAssignmentsController).
  describe "board membership" do
    include ActiveJob::TestHelper

    def grant_board(user) = post admin_role_assignments_path, params: { user_id: user.p_id, role: "board", return_to: "user" }

    # The roles form sends scope: "" for a role without scopes.
    def revoke_board(user, reason: "Left the board")
      post revoke_admin_role_assignments_path, params: { user_id: user.p_id, role: "board", scope: "", reason:, return_to: "user" }
    end

    it "lets an owner add a member to the board, with a log row and an email to the board" do
      sitting = create(:user, :verified, is_board: true)
      sign_in_via_magic_link(owner)

      perform_enqueued_jobs { grant_board(member) }

      expect(response).to redirect_to(admin_user_path(member, anchor: "roles"))
      expect(member.reload.is_board).to be(true)
      expect(IdentityGovernanceEvent.sole).to have_attributes(kind: "board_member_added", actor: owner, subject: member)
      expect(ActionMailer::Base.deliveries.flat_map(&:to)).to include(sitting.email, member.email)
      expect(UserRole.find_by!(user: member)).to have_attributes(granted_by: owner)
    end

    it "lets an owner take a member off the board, with a log row" do
      board = create(:user, :verified, is_board: true)
      sign_in_via_magic_link(owner)

      revoke_board(board)

      expect(board.reload.is_board).to be(false)
      expect(IdentityGovernanceEvent.sole).to have_attributes(kind: "board_member_removed", actor: owner, subject: board)
      expect(UserRole.find_by!(user: board)).to have_attributes(revoked_by: owner, revoke_reason: "Left the board")
    end

    it "writes the change to the permanent log with the owner as the actor, and clears the actor after the request" do
      sign_in_via_magic_link(owner)

      grant_board(member)

      expect(PrivilegedAttributeChange.where(user_id: member.id).sole)
        .to have_attributes(attribute_name: "role:board", role_key: "board", operation: "grant", old_value: "false",
                            new_value: "true", actor_id: owner.id, actor_label: "user #{owner.p_id}")
      expect(PrivilegedChangeActor.current).to eq(["", ""])
    end

    it "does not let an admin or a superadmin add themselves or another person to the board" do
      [admin, superadmin].each do |actor|
        sign_in_via_magic_link(actor)

        grant_board(actor)
        expect(flash[:alert]).to include("Not granted")
        grant_board(member)
        expect(flash[:alert]).to include("Not granted")
      end

      expect([admin, superadmin, member].map { |user| user.reload.is_board }).to all(be(false))
      expect(IdentityGovernanceEvent.count).to eq(0)
    end

    it "does not let a plain admin take a person off the board" do
      board = create(:user, :verified, is_board: true)
      sign_in_via_magic_link(admin)

      revoke_board(board)

      expect(flash[:alert]).to include("Not revoked")
      expect(board.reload.is_board).to be(true)
    end

    it "lets an owner add another owner to the board and take them off, from the user page" do
      other_owner = create(:user, :owner, :verified)
      sign_in_via_magic_link(owner)

      get admin_user_path(other_owner)
      expect(response.body).to include("Grant board member")

      grant_board(other_owner)
      expect(response).to redirect_to(admin_user_path(other_owner, anchor: "roles"))
      expect(other_owner.reload.is_board).to be(true)

      revoke_board(other_owner)
      expect(other_owner.reload.is_board).to be(false)
      expect(IdentityGovernanceEvent.order(:id).pluck(:kind)).to eq(%w[board_member_added board_member_removed])
    end

    it "lets an owner mark their own account, with a log row" do
      sign_in_via_magic_link(owner)

      grant_board(owner)

      expect(owner.reload.is_board).to be(true)
      expect(IdentityGovernanceEvent.sole).to have_attributes(kind: "board_member_added", actor: owner, subject: owner)
    end

    it "shows the roles section with the rule of each role, and the grant form only where the actor may use it" do
      sign_in_via_magic_link(admin)

      get admin_user_path(member)

      expect(response.body).to include("Roles", "One owner, at once, for any person, other owners too.", "Any admin, at once.",
                                       "An owner proposes. Every board member approves.", "Grant staff")
      expect(response.body).not_to include("Grant board member")
    end
  end

  describe "staff and contractor roles" do
    it "lets any admin grant and revoke staff and contractor for a person they manage, with a log row" do
      sign_in_via_magic_link(admin)

      post admin_role_assignments_path, params: { person: member.email, role: "staff", reason: "Hired" }
      post admin_role_assignments_path, params: { person: member.p_id, role: "contractor" }

      expect(response).to redirect_to(admin_role_assignments_path)
      expect(member.reload).to have_attributes(is_staff: true, is_contractor: true)
      expect(PrivilegedAttributeChange.where(user_id: member.id).pluck(:role_key)).to eq(%w[staff contractor])

      get admin_role_assignments_path
      expect(response.body).to include("Staff and contractors", member.full_name, "Reason: Hired")

      post revoke_admin_role_assignments_path, params: { user_id: member.p_id, role: "staff", reason: "Left" }
      expect(member.reload.is_staff).to be(false)
    end

    it "does not let an admin change the roles of a peer or a superior" do
      other_admin = create(:user, :admin, :verified)
      sign_in_via_magic_link(admin)

      post admin_role_assignments_path, params: { person: other_admin.p_id, role: "staff" }

      expect(flash[:alert]).to include("Not granted")
      expect(other_admin.reload.is_staff).to be(false)
    end

    it "refuses a role with a proposal rule, and an unknown role" do
      sign_in_via_magic_link(owner)

      post admin_role_assignments_path, params: { person: member.p_id, role: "verifier" }
      expect(flash[:alert]).to include("needs a proposal on the identity governance page")

      post admin_role_assignments_path, params: { person: member.p_id, role: "wizard" }
      expect(flash[:alert]).to eq("Unknown role.")
      expect(UserRole.count).to eq(0)
    end
  end
end
