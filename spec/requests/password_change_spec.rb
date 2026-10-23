# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Changing a password", type: :request do
  let(:directory) { use_fake_directory }
  let(:user) { create(:user, :verified) }

  def change_password(current:, new:, confirmation: new)
    patch password_path, params: { current_password: current, password: new, password_confirmation: confirmation }
  end

  context "with an AD account" do
    before do
      directory.add_user(user.p_id, password: "Ad-password-1")
      sign_in_via_magic_link(user)
    end

    it "shows the AD form" do
      get password_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Change your password")
      expect(response.body).to include("Forgot your password?")
    end

    it "changes the password in AD with the AD change form (delete + add)" do
      change_password(current: "Ad-password-1", new: "New-password-2")

      expect(response).to redirect_to(password_path)
      expect(directory.account(user.p_id).password).to eq("New-password-2")
      expect(directory.modifications.last[:operations].map(&:first)).to eq(%i[delete add])
      expect(user.reload.authenticate("New-password-2")).to be(false)
    end

    it "refuses a wrong current password" do
      change_password(current: "wrong", new: "New-password-2")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("current password is not correct")
    end

    it "shows a clear message when AD policy refuses the new password (0000052D)" do
      directory.modify_error = { code: 19, message: "0000052D: Constraint violation - check_password_restrictions" }

      change_password(current: "Ad-password-1", new: "short")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("does not meet the Patchwork password policy")
    end

    it "refuses a confirmation that does not match, without calling AD" do
      change_password(current: "Ad-password-1", new: "New-password-2", confirmation: "Other-password-3")

      expect(response.body).to include("not the same")
      expect(directory.modifications).to be_empty
    end

    it "resets a forgotten password with a replace, soon after an email-link sign-in" do
      change_password(current: "", new: "Reset-password-3")

      expect(response).to redirect_to(password_path)
      expect(directory.modifications.last[:operations].map(&:first)).to eq([:replace])
      expect(directory.account(user.p_id).password).to eq("Reset-password-3")
    end

    it "asks for the current password when the sign-in is older than 15 minutes" do
      travel 16.minutes do
        change_password(current: "", new: "Reset-password-3")
      end

      expect(response.body).to include("Enter your current password")
      expect(directory.modifications).to be_empty
    end
  end

  context "when Google sends a person without a Weave session" do
    before { directory.add_user(user.p_id, password: "Ad-password-1") }

    it "signs them in first and brings them back to /password" do
      get password_path
      expect(response).to redirect_to("/login")

      post "/login", params: { user: { email: user.email, password: "Ad-password-1" } }

      expect(response).to redirect_to(password_path)
      follow_redirect!
      expect(response.body).to include("Change your password")
    end
  end

  context "without an AD account" do
    it "lets an admin change their Weave password" do
      admin = create(:user, :admin, :verified)
      directory
      sign_in_via_magic_link(admin)

      change_password(current: "SecurePassword123!", new: "Another-Password-9!")

      expect(response).to redirect_to(password_path)
      expect(admin.reload.authenticate("Another-Password-9!")).to be_truthy
    end

    it "tells a member that the account has no password" do
      directory
      sign_in_via_magic_link(user)

      get password_path

      expect(response.body).to include("Your account has no password")
    end
  end

  context "when AD is unreachable" do
    it "says so instead of changing the Weave password" do
      directory.add_user(user.p_id, password: "Ad-password-1")
      sign_in_via_magic_link(user)
      directory.down_hosts.push("loom.patchwork.internal", "spindle.patchwork.internal")

      get password_path

      expect(response.body).to include("can't reach the Patchwork directory")
    end
  end

  describe "admin reset" do
    let(:superadmin) { create(:user, :superadmin, :verified) }

    before do
      directory.add_user(user.p_id, password: "Ad-password-1")
      sign_in_via_magic_link(superadmin)
    end

    it "writes the new password to AD with a replace and not to Weave" do
      patch admin_user_path(user), params: { user: { first_name: user.first_name, password: "Admin-reset-4", password_confirmation: "Admin-reset-4" } }

      expect(response).to redirect_to(admin_user_path(user))
      expect(directory.account(user.p_id).password).to eq("Admin-reset-4")
      expect(directory.modifications.last[:operations].map(&:first)).to eq([:replace])
      expect(user.reload.authenticate("Admin-reset-4")).to be(false)
    end

    it "shows the AD policy refusal and saves nothing" do
      directory.modify_error = { code: 19, message: "0000052D: Constraint violation" }

      patch admin_user_path(user), params: { user: { first_name: "Changed", password: "short", password_confirmation: "short" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("does not meet the Active Directory password policy")
      expect(user.reload.first_name).not_to eq("Changed")
    end
  end
end
