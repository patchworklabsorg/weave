# frozen_string_literal: true

require "rails_helper"

# Every impersonation leaves an Impersonation row. Admins see the history on
# the admin user page; the impersonated user never sees it.
RSpec.describe "Impersonation audit log", type: :request do
  let(:owner) { create(:user, :owner, :verified) }
  let(:member) { create(:user, :verified) }

  describe "recording" do
    before { sign_in_via_magic_link(owner) }

    it "records who started impersonating whom, and from where" do
      expect { post impersonate_admin_user_path(member) }.to change(Impersonation, :count).by(1)

      impersonation = Impersonation.last
      expect(impersonation).to have_attributes(admin: owner, user: member, denied: false, ended_at: nil)
      expect(impersonation.ip).to be_present
      expect(impersonation).to be_active
    end

    it "ends the row when the admin stops impersonating" do
      post impersonate_admin_user_path(member)

      delete stop_impersonating_admin_users_path

      expect(Impersonation.last).to have_attributes(end_reason: "stopped")
      expect(Impersonation.last.ended_at).to be_present
    end

    it "ends the row when the admin logs out while impersonating" do
      post impersonate_admin_user_path(member)

      delete logout_path

      expect(Impersonation.last).to have_attributes(end_reason: "logged_out")
    end

    it "keeps the row when the impersonated user is deleted" do
      post impersonate_admin_user_path(member)
      delete stop_impersonating_admin_users_path

      member.destroy!

      expect(Impersonation.last).to have_attributes(admin: owner, user: nil)
    end
  end

  it "records a denied attempt by an admin who may not impersonate" do
    admin = create(:user, :admin, :verified)
    sign_in_via_magic_link(admin)

    expect { post impersonate_admin_user_path(member) }.to change(Impersonation, :count).by(1)

    expect(Impersonation.last).to have_attributes(admin: admin, user: member, denied: true)
    expect(session[:admin_id]).to be_nil
  end

  describe "visibility" do
    before do
      sign_in_via_magic_link(owner)
      post impersonate_admin_user_path(member)
      delete stop_impersonating_admin_users_path
    end

    it "shows the history to an admin on the user page" do
      get admin_user_path(member)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Impersonations")
      expect(response.body).to include(owner.full_name)
      expect(response.body).to include("Stop impersonating")
    end

    it "keeps a member out of the admin user page" do
      delete logout_path
      sign_in_via_magic_link(member)

      get admin_user_path(member)

      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to include(owner.email)
    end

    it "does not show it on the member's own pages" do
      delete logout_path
      sign_in_via_magic_link(member)

      [root_path, edit_profile_path, profile_sessions_path].each do |path|
        get path
        expect(response.body).not_to include("Impersonations")
        expect(response.body).not_to include(owner.email)
      end
    end
  end
end
