# frozen_string_literal: true

require "rails_helper"

# The app launcher on /profile (see AppLauncher): the apps a member may use,
# the ones they may ask for, and their open requests.
RSpec.describe "App launcher", type: :request do
  let(:member) { create(:user, :verified, :accepted_code_of_conduct) }
  let(:group) { create(:group, name: "Reviewers") }

  def launcher_app(name, **attributes)
    Doorkeeper::Application.create!(name:, redirect_uri: "https://#{name.parameterize}.example.com/callback",
                                    show_in_launcher: true, launch_url: "https://#{name.parameterize}.example.com",
                                    **attributes)
  end

  before { sign_in_via_magic_link(member) }

  it "lists the apps the member can use, with links" do
    launcher_app("Open App", launcher_description: "For everyone")

    get profile_path

    expect(response.body).to include("Your apps", "Open App", "For everyone", "https://open-app.example.com")
  end

  it "leaves out apps that are not in the launcher" do
    Doorkeeper::Application.create!(name: "Hidden App", redirect_uri: "https://hidden.example.com/callback",
                                    launch_url: "https://hidden.example.com")

    get profile_path

    expect(response.body).not_to include("Hidden App")
    expect(response.body).not_to include("Your apps")
  end

  it "leaves out restricted apps that take no requests" do
    launcher_app("Secret App", access_policy: "restricted")

    get profile_path

    expect(response.body).not_to include("Secret App")
  end

  it "offers a request for a restricted app with an access request group" do
    application = launcher_app("Krater", access_policy: "restricted")
    ApplicationAccessGrant.create!(application:, grantee: group)
    application.update!(access_request_group: group)

    get profile_path

    expect(response.body).to include("Krater", "Request access", new_access_request_path(application: application.to_param))
    expect(response.body).not_to include("https://krater.example.com\"")
  end

  it "shows a pending request" do
    application = launcher_app("Krater", access_policy: "restricted")
    ApplicationAccessGrant.create!(application:, grantee: group)
    application.update!(access_request_group: group)
    AccessRequest.create!(user: member, application:, group:, reason: "Please")

    get profile_path

    expect(response.body).to include("Request pending")
    expect(response.body).not_to include(new_access_request_path(application: application.to_param))
  end

  it "links a manager to the groups they manage" do
    create(:group_membership, group:, user: member, role: "manager")

    get profile_path

    expect(response.body).to include("Groups you manage", groups_path)
  end
end
