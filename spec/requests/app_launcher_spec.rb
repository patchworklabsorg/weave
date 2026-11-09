# frozen_string_literal: true

require "rails_helper"

# The app launcher on the member home (/) (see AppLauncher): the apps a member may use,
# the ones they may ask for, and their open requests.
RSpec.describe "App launcher", type: :request do
  let(:member) do
    create(:user, :verified, :accepted_code_of_conduct, slack_id: "U1", slack_membership: "member")
  end
  let(:group) { create(:group, name: "Reviewers") }

  def launcher_app(name, **attributes)
    Doorkeeper::Application.create!(name:, redirect_uri: "https://#{name.parameterize}.example.com/callback",
                                    show_in_launcher: true, launch_url: "https://#{name.parameterize}.example.com",
                                    **attributes)
  end

  before { sign_in_via_magic_link(member) }

  it "lists the apps the member can use, with links" do
    launcher_app("Open App", launcher_description: "For everyone")

    get root_path

    expect(response.body).to include("Your apps", "Open App", "For everyone", "https://open-app.example.com")
  end

  it "leaves out apps that are not in the launcher" do
    Doorkeeper::Application.create!(name: "Hidden App", redirect_uri: "https://hidden.example.com/callback",
                                    launch_url: "https://hidden.example.com")

    get root_path

    expect(response.body).not_to include("Hidden App")
    expect(response.body).not_to include("Your apps")
  end

  it "leaves out restricted apps that take no requests" do
    launcher_app("Secret App", access_policy: "restricted")

    get root_path

    expect(response.body).not_to include("Secret App")
  end

  it "offers a request for a restricted app with an access request group" do
    application = launcher_app("Krater", access_policy: "restricted")
    ApplicationAccessGrant.create!(application:, grantee: group)
    application.update!(access_request_group: group)

    get root_path

    expect(response.body).to include("Krater", "Request access", new_access_request_path(application: application.to_param))
    expect(response.body).not_to include("https://krater.example.com\"")
  end

  it "offers requests for several apps without an N+1 query" do
    %w[Krater Compute].each do |name|
      application = launcher_app(name, access_policy: "restricted")
      ApplicationAccessGrant.create!(application:, grantee: group)
      application.update!(access_request_group: group)
    end

    get root_path

    expect(response.body.scan("Request access").size).to eq(2)
  end

  it "shows a pending request" do
    application = launcher_app("Krater", access_policy: "restricted")
    ApplicationAccessGrant.create!(application:, grantee: group)
    application.update!(access_request_group: group)
    AccessRequest.create!(user: member, application:, group:, reason: "Please")

    get root_path

    expect(response.body).to include("Request pending")
    expect(response.body).not_to include(new_access_request_path(application: application.to_param))
  end

  it "asks a manager to review a waiting access request" do
    create(:group_membership, group:, user: member, role: "manager")
    application = launcher_app("Krater", access_policy: "restricted")
    ApplicationAccessGrant.create!(application:, grantee: group)
    application.update!(access_request_group: group)
    AccessRequest.create!(user: create(:user, :verified), application:, group:, reason: "Please")

    get root_path

    expect(response.body).to include("To do", "1 access request waits for you", groups_path)
  end

  it "does not ask a manager to review their own request" do
    create(:group_membership, group:, user: member, role: "manager")
    application = launcher_app("Krater", access_policy: "restricted")
    ApplicationAccessGrant.create!(application:, grantee: group)
    application.update!(access_request_group: group)
    AccessRequest.create!(user: member, application:, group:, reason: "Please")

    get root_path

    expect(response.body).not_to include("To do")
    expect(response.body).not_to include("Request pending")
  end

  it "shows no to do list to a manager with nothing waiting" do
    create(:group_membership, group:, user: member, role: "manager")

    get root_path

    expect(response.body).not_to include("To do")
  end

  it "shows no apps until the email address is confirmed" do
    launcher_app("Open App")
    member.update!(email_confirmed_at: nil)

    get root_path

    expect(response).to redirect_to(email_confirmation_path)
  end

  it "keeps the launcher off the account page" do
    launcher_app("Open App")

    get profile_path

    expect(response.body).not_to include("Your apps")
  end
end
