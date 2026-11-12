# frozen_string_literal: true

require "rails_helper"

# An OAuth app can belong to one patch. Any admin who can edit apps sets it.
RSpec.describe "Admin OAuth application patch", type: :request do
  let(:admin) { create(:user, :admin, :verified) }
  let!(:ganymede) { create(:patch, slug: "ganymede", name: "Project Ganymede") }
  let(:application) { Doorkeeper::Application.create!(name: "Krater", redirect_uri: "https://krater.example.com/cb") }

  before { sign_in_via_magic_link(admin) }

  it "links an app to a patch, and shows the patch on the app page and the app on the patch page" do
    get edit_admin_oauth_application_path(application)
    expect(response.body).to include("Project Ganymede (ganymede)")

    patch admin_oauth_application_path(application), params: { doorkeeper_application: { patch_id: ganymede.id } }

    expect(application.reload.patch).to eq(ganymede)
    get admin_oauth_application_path(application)
    expect(response.body).to include("Project Ganymede", admin_patch_path(ganymede))
    get admin_patch_path(ganymede)
    expect(response.body).to include("Krater")
  end

  it "removes the link" do
    application.update!(patch: ganymede)

    patch admin_oauth_application_path(application), params: { doorkeeper_application: { patch_id: "" } }

    expect(application.reload.patch).to be_nil
  end

  it "refuses a patch that does not exist" do
    patch admin_oauth_application_path(application), params: { doorkeeper_application: { patch_id: ganymede.id + 1000 } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(application.reload.patch).to be_nil
  end

  it "sets the patch when an app is created" do
    post admin_oauth_applications_path, params: {
      doorkeeper_application: { name: "Orbit", redirect_uri: "https://orbit.example.com/cb", scopes: "openid patches", patch_id: ganymede.id }
    }

    expect(Doorkeeper::Application.find_by!(name: "Orbit").patch).to eq(ganymede)
  end

  it "is not open to a member" do
    sign_in_via_magic_link(create(:user, :verified))

    patch admin_oauth_application_path(application), params: { doorkeeper_application: { patch_id: ganymede.id } }

    # The admin routes do not exist for a member (AdminConstraint).
    expect(response).to have_http_status(:not_found)
    expect(application.reload.patch).to be_nil
  end
end
