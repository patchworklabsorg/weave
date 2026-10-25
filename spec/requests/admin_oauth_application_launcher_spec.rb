# frozen_string_literal: true

require "rails_helper"

# Launcher fields and the access request group of an OAuth app (see
# OauthApplicationLauncher). Choosing the group decides who may give access,
# so only a superadmin may.
RSpec.describe "Admin OAuth application launcher", type: :request do
  let(:superadmin) { create(:user, :superadmin, :verified) }
  let(:group) { create(:group, name: "Reviewers") }
  let(:application) do
    Doorkeeper::Application.create!(name: "Krater", redirect_uri: "https://krater.example.com/callback", access_policy: "restricted")
  end

  it "saves the launcher fields" do
    sign_in_via_magic_link(superadmin)

    patch admin_oauth_application_path(application), params: { doorkeeper_application: {
      show_in_launcher: "1", launch_url: "https://krater.example.com", launcher_description: "Review proposals"
    }
}

    expect(application.reload).to have_attributes(show_in_launcher: true, launch_url: "https://krater.example.com",
                                                  launcher_description: "Review proposals")
  end

  it "refuses an icon that is not https" do
    sign_in_via_magic_link(superadmin)

    patch admin_oauth_application_path(application), params: { doorkeeper_application: { launcher_icon_url: "javascript:alert(1)" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(application.reload.launcher_icon_url).to be_nil
  end

  it "sets the access request group to a group with access" do
    ApplicationAccessGrant.create!(application:, grantee: group)
    sign_in_via_magic_link(superadmin)

    patch access_request_group_admin_oauth_application_path(application), params: { group_id: group.public_id }

    expect(application.reload.access_request_group).to eq(group)
  end

  it "refuses a sponsored project group" do
    group.update!(waives_code_of_conduct: true)
    ApplicationAccessGrant.create!(application:, grantee: group)
    sign_in_via_magic_link(superadmin)

    patch access_request_group_admin_oauth_application_path(application), params: { group_id: group.public_id }

    expect(application.reload.access_request_group).to be_nil
  end

  it "refuses a group without access to the app" do
    sign_in_via_magic_link(superadmin)

    patch access_request_group_admin_oauth_application_path(application), params: { group_id: group.public_id }

    expect(flash[:alert]).to include("must have access to the app")
    expect(application.reload.access_request_group).to be_nil
  end

  it "is closed to a plain admin" do
    ApplicationAccessGrant.create!(application:, grantee: group)
    sign_in_via_magic_link(create(:user, :admin, :verified))

    patch access_request_group_admin_oauth_application_path(application), params: { group_id: group.public_id }

    expect(application.reload.access_request_group).to be_nil
  end

  it "stops requests" do
    ApplicationAccessGrant.create!(application:, grantee: group)
    application.update!(access_request_group: group)
    sign_in_via_magic_link(superadmin)

    patch access_request_group_admin_oauth_application_path(application), params: { group_id: "" }

    expect(application.reload.access_request_group).to be_nil
  end

  it "shows the access request group on the app page" do
    ApplicationAccessGrant.create!(application:, grantee: group)
    application.update!(access_request_group: group)
    sign_in_via_magic_link(superadmin)

    get admin_oauth_application_path(application)

    expect(response.body).to include("Members can ask for access", "Reviewers")
  end
end
