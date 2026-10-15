# frozen_string_literal: true

require "rails_helper"

# Admin URLs for OAuth applications use the public id (hashid), not the
# database id. The OAuth client_id (`uid`) does not change.
RSpec.describe "Admin OAuth application public ids", type: :request do
  let(:admin) { create(:user, :admin, :verified) }
  let(:application) do
    Doorkeeper::Application.create!(
      name: "Quilt", redirect_uri: "https://quilt.example.com/cb", scopes: "openid profile email roles directory introspect"
    )
  end

  before { sign_in_via_magic_link(admin) }

  it "uses the public id in the URL helpers" do
    expect(admin_oauth_application_path(application)).to eq("/admin/oauth_applications/#{application.hashid}")
    expect(application.hashid).not_to eq(application.id.to_s)
    expect(application.public_id).to start_with("app_")
  end

  it "does not change the client_id" do
    expect(application.uid).not_to eq(application.hashid)
    expect(application.uid).to be_present
  end

  it "shows the app at its public id URL" do
    get admin_oauth_application_path(application)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Quilt")
  end

  it "returns 404 for the numeric database id on every verb" do
    get "/admin/oauth_applications/#{application.id}"
    expect(response).to have_http_status(:not_found)

    get "/admin/oauth_applications/#{application.id}/edit"
    expect(response).to have_http_status(:not_found)

    patch "/admin/oauth_applications/#{application.id}", params: { doorkeeper_application: { name: "Changed" } }
    expect(response).to have_http_status(:not_found)
    expect(application.reload.name).to eq("Quilt")
  end

  it "accepts a group public id and rejects the numeric group id when granting access" do
    group = Group.create!(name: "Testers", slug: "testers")

    post admin_oauth_application_access_grants_path(application), params: { access_grant: { group_id: group.id } }
    expect(ApplicationAccessGrant.count).to eq(0)
  end

  it "returns 404 for an unknown id" do
    get "/admin/oauth_applications/nope"

    expect(response).to have_http_status(:not_found)
  end

  it "finds the app for nested routes by public id only" do
    post admin_oauth_application_roles_path(application), params: { role: { key: "admin", name: "Admin" } }
    expect(response).not_to have_http_status(:not_found)

    post "/admin/oauth_applications/#{application.id}/roles", params: { role: { key: "x", name: "X" } }
    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 for the numeric id of a service" do
    service = Service.create!(name: "Svc", created_by: admin)

    get admin_service_path(service)
    expect(response).not_to have_http_status(:not_found)

    get "/admin/services/#{service.id}"
    expect(response).to have_http_status(:not_found)
  end

  describe "index" do
    before { application }

    it "links the name to the public id URL" do
      get admin_oauth_applications_path

      expect(response.body).to include(%(href="#{admin_oauth_application_path(application)}"))
      expect(response.body).not_to include(%(href="/admin/oauth_applications/#{application.id}"))
    end

    it "renders each scope as its own chip inside a scrollable wrapper" do
      get admin_oauth_applications_path

      doc = Nokogiri::HTML(response.body)
      chips = doc.css('ul[aria-label="Scopes"] li').map { |li| li.text.strip }
      expect(chips).to eq(%w[openid profile email roles directory introspect])
      expect(doc.at_css(".overflow-x-auto table")).to be_present
    end
  end
end
