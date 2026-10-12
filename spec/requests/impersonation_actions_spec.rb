# frozen_string_literal: true

require "rails_helper"

# What an admin does while impersonating is recorded on the Impersonation row:
# each request as an Impersonation::Action, each record change as a PaperTrail
# version that names the admin and points to the impersonation. Only admins
# can see it.
RSpec.describe "Impersonation actions", type: :request do
  let(:owner) { create(:user, :owner, :verified) }
  let(:member) { create(:user, :verified, :accepted_code_of_conduct, first_name: "Ada") }

  def impersonate
    sign_in_via_magic_link(owner)
    post impersonate_admin_user_path(member)
    Impersonation.last
  end

  describe "recording" do
    it "records a change made while impersonating on the open impersonation" do
      impersonation = impersonate

      expect do
        patch update_profile_path, params: { user: { first_name: "Grace" } }
      end.to change(impersonation.actions, :count).by(1)

      action = impersonation.actions.last
      expect(action).to have_attributes(http_method: "PATCH", path: "/profile", controller_action: "users#update", status: 302)
      expect(action.params).to eq("user" => { "first_name" => "Grace" })
    end

    it "records the pages the admin opens, but not polling or partial requests" do
      impersonation = impersonate

      get edit_profile_path
      get edit_profile_path, headers: { "Accept" => "application/json" }
      get edit_profile_path, xhr: true

      expect(impersonation.actions.pluck(:http_method, :path)).to eq([["GET", "/profile/edit"]])
    end

    it "records the request that stops the impersonation" do
      impersonation = impersonate

      delete stop_impersonating_admin_users_path

      expect(impersonation.actions.last).to have_attributes(http_method: "DELETE", controller_action: "admin/users#stop_impersonating")
    end

    it "records nothing without an impersonation" do
      sign_in_via_magic_link(member)

      expect do
        patch update_profile_path, params: { user: { first_name: "Grace" } }
      end.not_to change(Impersonation::Action, :count)
    end

    it "never stores sensitive values" do
      impersonation = impersonate

      patch update_profile_path, params: {
        user: { first_name: "Grace", email: "new@example.com", password: "hunter2hunter2" },
        cropped_image_data: "data:image/png;base64,#{'A' * 5_000}",
        token: "secret-token",
        note: "B" * 1_000
      }

      stored = impersonation.actions.last.params.to_json
      expect(stored).not_to include("new@example.com", "hunter2hunter2", "secret-token", "AAAA")
      expect(stored).to include("[FILTERED]", "Grace")
      expect(impersonation.actions.last.params["note"].length).to eq(RecordsImpersonationActions::MAX_VALUE_LENGTH)
    end

    it "keeps recording failures away from the request" do
      impersonation = impersonate
      allow(Impersonation::Action).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "boom")

      patch update_profile_path, params: { user: { first_name: "Grace" } }

      expect(response).to have_http_status(:redirect)
      expect(member.reload.first_name).to eq("Grace")
      expect(impersonation.actions).to be_empty
    end

    it "attributes record changes to the admin and the impersonation" do
      impersonation = impersonate

      patch update_profile_path, params: { user: { first_name: "Grace" } }

      version = member.versions.last
      expect(version.whodunnit).to eq(owner.id.to_s)
      expect(version.impersonation_id).to eq(impersonation.id)
      expect(impersonation.versions).to include(version)
    end

    it "leaves record changes outside an impersonation with no impersonation" do
      sign_in_via_magic_link(member)

      patch update_profile_path, params: { user: { first_name: "Grace" } }

      expect(member.versions.last).to have_attributes(whodunnit: member.id.to_s, impersonation_id: nil)
    end

    it "records an OAuth consent given while impersonating" do
      application = Doorkeeper::Application.create!(
        name: "Test Client", redirect_uri: "https://client.example.com/callback", scopes: "openid email", confidential: false
      )
      impersonation = impersonate

      post oauth_authorization_path, params: {
        client_id: application.uid, redirect_uri: application.redirect_uri, response_type: "code", scope: "openid email",
        code_challenge: Base64.urlsafe_encode64(OpenSSL::Digest::SHA256.digest("v" * 64), padding: false),
        code_challenge_method: "S256"
      }

      action = impersonation.actions.find_by(controller_action: "oauth/authorizations#create")
      expect(action).to have_attributes(http_method: "POST", path: "/oauth/authorize")
      expect(action.params).to include("client_id" => application.uid)
    end
  end

  describe "visibility" do
    let!(:impersonation) do
      impersonate.tap do
        patch update_profile_path, params: { user: { first_name: "Grace" } }
        delete stop_impersonating_admin_users_path
      end
    end

    it "shows an admin the actions and record changes under the impersonation" do
      get admin_user_path(member)
      expect(response.body).to include(admin_user_impersonation_path(member, impersonation))

      get admin_user_impersonation_path(member, impersonation)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("users#update", "/profile", "PATCH", "User #")
    end

    it "keeps a member out" do
      delete logout_path
      sign_in_via_magic_link(member)

      get admin_user_impersonation_path(member, impersonation)

      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to include("users#update")
    end

    it "keeps an admin out when they may not view the user" do
      delete logout_path
      sign_in_via_magic_link(create(:user, :admin, :verified))

      get admin_user_impersonation_path(owner, Impersonation.create!(admin: member, user: owner, started_at: Time.current))

      expect(response).to redirect_to(admin_users_path)
    end
  end
end
