# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin service keys", type: :request do
  let(:superadmin) { create(:user, :superadmin, :verified) }
  let(:admin) { create(:user, :admin, :verified) }
  let(:service) { create(:service, name: "Krater") }
  let(:key) { create(:service_key, service:, name: "Production") }

  context "when signed in as a superadmin" do
    before { sign_in_via_magic_link(superadmin) }

    it "shows the new key once, in the create response, and stores only its digest" do
      get new_admin_service_key_path(service)
      expect(response).to have_http_status(:ok)

      post admin_service_keys_path(service), params: { service_key: { name: "Staging" } }

      raw = response.body[/pwl_[A-Za-z0-9_-]{20,}/]
      created = service.keys.sole
      expect(Service::Key.find_by_api_key(raw)).to eq(created) # rubocop:disable Rails/DynamicFindBy

      get admin_service_key_path(service, created)
      expect(response.body).not_to include(raw)
    end

    it "shows the recent requests of a key" do
      key.usages.create!(request_path: "/api/v1/directory/users", request_method: "GET", response_code: 200, requested_at: Time.current)

      get admin_service_key_path(service, key)

      expect(response.body).to include("GET /api/v1/directory/users")
    end

    it "renames, deprecates, revokes and activates a key" do
      get edit_admin_service_key_path(service, key)
      expect(response).to have_http_status(:ok)

      patch admin_service_key_path(service, key), params: { service_key: { name: "Primary" } }
      expect(key.reload.name).to eq("Primary")

      patch deprecate_admin_service_key_path(service, key)
      expect(key.reload).to be_deprecated

      patch revoke_admin_service_key_path(service, key)
      expect(key.reload).to be_revoked

      patch activate_admin_service_key_path(service, key)
      expect(key.reload).to be_active
    end

    it "deletes a key" do
      delete admin_service_key_path(service, key)
      expect(response).to redirect_to(admin_service_path(service, anchor: "keys"))
      expect(Service::Key.exists?(key.id)).to be(false)
    end

    it "sends the key list to the service page" do
      get admin_service_keys_path(service)

      expect(response).to redirect_to(admin_service_path(service, anchor: "keys"))
    end
  end

  context "when signed in as a plain admin" do
    before { sign_in_via_magic_link(admin) }

    it "can view a key, but not create or revoke one" do
      get admin_service_key_path(service, key)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Revoke")

      post admin_service_keys_path(service), params: { service_key: { name: "Sneaky" } }
      patch revoke_admin_service_key_path(service, key)

      expect(service.keys).to contain_exactly(key)
      expect(key.reload).to be_active
      expect(flash[:alert]).to include("Only a superadmin")
    end
  end
end
