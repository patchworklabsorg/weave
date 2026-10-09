# frozen_string_literal: true

require "rails_helper"

# Apps check users again without a browser session. The directory shows only
# what the app could see in claims at sign-in.
RSpec.describe "Directory API", type: :request do
  let(:application) do
    Doorkeeper::Application.create!(name: "Krater", redirect_uri: "https://krater.example.com/cb",
                                    scopes: "openid profile groups roles directory", access_policy: "restricted")
  end
  let(:reviewer) { create(:user, :verified, :accepted_code_of_conduct, slack_id: "U0REVIEW") }
  let(:reviewers) { create(:group, name: "Krater Reviewers") }
  let(:role) { ApplicationRole.create!(application: application, key: "reviewer", name: "Reviewer") }

  def app_token(app = application, scopes: "directory")
    Doorkeeper::AccessToken.create!(application: app, scopes: scopes).plaintext_token
  end

  def directory_get(path, token: app_token, params: {})
    get path, params: params, headers: { "Authorization" => "Bearer #{token}" }
    response.parsed_body
  end

  before do
    create(:group_membership, group: reviewers, user: reviewer)
    ApplicationRoleAssignment.create!(role: role, assignee: reviewers)
  end

  describe "GET /api/v1/directory/users/:sub" do
    it "returns the user with this app's groups and roles" do
      body = directory_get(api_v1_directory_user_path(reviewer.p_id))

      expect(response).to have_http_status(:ok)
      expect(body).to eq(
        "sub" => reviewer.p_id, "name" => reviewer.full_name, "email" => reviewer.email,
        "email_verified" => true, "slack_id" => "U0REVIEW", "slack_member" => reviewer.slack_member?,
        "groups" => ["krater-reviewers"], "roles" => ["reviewer"], "active" => true
      )
    end

    it "hides groups and roles that are not linked to the app" do
      other = Doorkeeper::Application.create!(name: "Other", redirect_uri: "https://other.example.com/cb")
      other_role = ApplicationRole.create!(application: other, key: "owner", name: "Owner")
      ApplicationRoleAssignment.create!(role: other_role, assignee: reviewer)
      create(:group_membership, group: create(:group, name: "Payroll"), user: reviewer)

      body = directory_get(api_v1_directory_user_path(reviewer.p_id))

      expect(body).to include("groups" => ["krater-reviewers"], "roles" => ["reviewer"])
    end

    it "is not found for a user the app may not serve" do
      directory_get(api_v1_directory_user_path(create(:user, :verified, :accepted_code_of_conduct).p_id))

      expect(response).to have_http_status(:not_found)
    end

    it "is not found for an unknown sub" do
      directory_get(api_v1_directory_user_path("PWL0000000000"))

      expect(response).to have_http_status(:not_found)
    end

    it "marks a user who can no longer sign in as inactive" do
      ApplicationRoleAssignment.create!(role: role, assignee: reviewer)
      reviewer.update_column(:locked_at, Time.current) # rubocop:disable Rails/SkipsModelValidations

      expect(directory_get(api_v1_directory_user_path(reviewer.p_id))).to include("active" => false)
    end
  end

  describe "GET /api/v1/directory/users" do
    it "lists users who hold a role, directly or through a group" do
      direct = create(:user, :verified, :accepted_code_of_conduct)
      ApplicationRoleAssignment.create!(role: role, assignee: direct)

      body = directory_get(api_v1_directory_users_path, params: { role: "reviewer" })

      expect(body["users"].pluck("sub")).to contain_exactly(reviewer.p_id, direct.p_id)
    end

    it "lists members of a linked group" do
      body = directory_get(api_v1_directory_users_path, params: { group: "krater-reviewers" })

      expect(body["users"].pluck("sub")).to eq([reviewer.p_id])
    end

    it "is not found for a group that is not linked to the app" do
      create(:group, name: "Payroll")

      directory_get(api_v1_directory_users_path, params: { group: "payroll" })

      expect(response).to have_http_status(:not_found)
    end

    it "is not found for a role of another app" do
      directory_get(api_v1_directory_users_path, params: { role: "owner" })

      expect(response).to have_http_status(:not_found)
    end

    it "needs exactly one of role or group" do
      directory_get(api_v1_directory_users_path)
      expect(response).to have_http_status(:bad_request)

      directory_get(api_v1_directory_users_path, params: { role: "reviewer", group: "krater-reviewers" })
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "authentication" do
    let(:path) { api_v1_directory_user_path(reviewer.p_id) }

    it "refuses a request without a token" do
      get path

      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a token without the directory scope" do
      directory_get(path, token: app_token(scopes: "profile"))

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses a user's token, even with the directory scope" do
      token = Doorkeeper::AccessToken.create!(application: application, resource_owner_id: reviewer.id, scopes: "directory")

      directory_get(path, token: token.plaintext_token)

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses an app that is not allowed the directory scope" do
      other = Doorkeeper::Application.create!(name: "Other", redirect_uri: "https://other.example.com/cb", scopes: "openid profile")

      directory_get(path, token: app_token(other))

      expect(response).to have_http_status(:forbidden)
    end

    it "refuses an app with no scope list, which may ask for any scope" do
      other = Doorkeeper::Application.create!(name: "Other", redirect_uri: "https://other.example.com/cb")

      directory_get(path, token: app_token(other))

      expect(response).to have_http_status(:forbidden)
    end

    it "issues a directory token through client_credentials" do
      post oauth_token_path, params: { grant_type: "client_credentials", scope: "directory" },
                             headers: { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials(application.uid, application.plaintext_secret) }
      token = response.parsed_body.fetch("access_token")

      directory_get(path, token: token)

      expect(response).to have_http_status(:ok)
    end
  end
end
