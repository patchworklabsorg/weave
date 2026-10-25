# frozen_string_literal: true

require "rails_helper"

# A service key reads the directory and a webhook sends user data out of
# Weave, so any admin may look at services, and only a superadmin may change
# them.
RSpec.describe "Admin services", type: :request do
  let(:superadmin) { create(:user, :superadmin, :verified) }
  let(:admin) { create(:user, :admin, :verified) }
  let!(:service) { create(:service, name: "Krater", description: "Grants") }

  context "when signed in as a superadmin" do
    before { sign_in_via_magic_link(superadmin) }

    it "lists and searches services" do
      create(:service, name: "Loom")

      get admin_services_path
      expect(response.body).to include("Krater", "Loom", "New service")

      get admin_services_path(search: "kra")
      expect(response.body).to include("Krater")
      expect(response.body).not_to include("Loom")
    end

    it "shows a service with its keys and webhooks" do
      key = create(:service_key, service:, name: "Production")
      create(:service_webhook, service:, event_type: "group.member_added", url: "https://krater.example.com/hook")

      get admin_service_path(service)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Production", "group.member_added", "https://krater.example.com/hook", admin_service_key_path(service, key))
    end

    it "creates, edits and deletes a service" do
      get new_admin_service_path
      expect(response).to have_http_status(:ok)

      post admin_services_path, params: { service: { name: "Loom", description: "Weaving" } }
      loom = Service.find_by!(name: "Loom")
      expect(response).to redirect_to(admin_service_path(loom))
      expect(loom.created_by).to eq(superadmin)

      get edit_admin_service_path(loom)
      expect(response).to have_http_status(:ok)

      patch admin_service_path(loom), params: { service: { name: "Loom 2" } }
      expect(loom.reload.name).to eq("Loom 2")

      delete admin_service_path(loom)
      expect(Service.exists?(loom.id)).to be(false)
    end

    it "shows the form errors for a duplicate name" do
      post admin_services_path, params: { service: { name: "Krater" } }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "suspends and activates a service" do
      patch suspend_admin_service_path(service)
      expect(service.reload).to be_suspended

      patch activate_admin_service_path(service)
      expect(service.reload).to be_active
    end
  end

  context "when signed in as a plain admin" do
    before { sign_in_via_magic_link(admin) }

    it "can list and view services, without the change actions" do
      get admin_services_path
      expect(response.body).to include("Krater")
      expect(response.body).not_to include("New service")

      get admin_service_path(service)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Suspend", "New key", "New webhook")
    end

    it "can't create, change or delete a service" do
      post admin_services_path, params: { service: { name: "Sneaky" } }
      expect(response).to redirect_to(admin_services_path)
      expect(Service.exists?(name: "Sneaky")).to be(false)

      patch admin_service_path(service), params: { service: { name: "Renamed" } }
      patch suspend_admin_service_path(service)
      delete admin_service_path(service)

      expect(service.reload.attributes.values_at("name", "status")).to eq(%w[Krater active])
    end
  end

  it "is in the admin sidebar" do
    sign_in_via_magic_link(admin)

    get admin_services_path

    expect(response.body).to include(%(href="#{admin_services_path}"))
  end
end
