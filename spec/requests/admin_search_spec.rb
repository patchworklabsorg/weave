# frozen_string_literal: true

require "rails_helper"

# The ⌘K command bar asks this endpoint for users, groups and OAuth apps.
# It is admin-only, JSON-only, and returns a flat list of
# { type, label, hint, path }.
RSpec.describe "Admin search", type: :request do
  let(:admin) { create(:user, :admin, :verified) }
  let!(:member) { create(:user, :verified, first_name: "Ada", last_name: "Lovelace", email: "ada@example.com") }
  let!(:group) { create(:group, name: "Analytical Engines", slug: "engines") }
  let!(:application) do
    Doorkeeper::Application.create!(name: "Adagio", redirect_uri: "https://adagio.example.com/cb", scopes: "profile")
  end

  def results
    JSON.parse(response.body)
  end

  context "when signed in as an admin" do
    before { sign_in_via_magic_link(admin) }

    it "finds users, groups and apps by a partial match" do
      get admin_search_path(q: "ada", format: :json)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")

      user_hit = results.find { |r| r["type"] == "user" && r["label"] == "Ada Lovelace" }
      expect(user_hit).to include("hint" => "ada@example.com", "path" => admin_user_path(member))

      app_hit = results.find { |r| r["type"] == "application" }
      expect(app_hit).to include("label" => "Adagio", "hint" => application.uid, "path" => admin_oauth_application_path(application))

      expect(results.map { |r| r["type"] }).not_to include("group")
    end

    it "finds groups by name or slug" do
      get admin_search_path(q: "engines", format: :json)

      expect(results).to include(a_hash_including("type" => "group", "label" => "Analytical Engines", "path" => admin_group_path(group)))
    end

    it "finds a user by PWL id" do
      get admin_search_path(q: member.p_id, format: :json)

      expect(results).to include(a_hash_including("type" => "user", "label" => "Ada Lovelace"))
    end

    it "returns nothing for a query under two characters" do
      get admin_search_path(q: "a", format: :json)

      expect(results).to eq([])
    end

    it "treats SQL wildcards as plain text" do
      get admin_search_path(q: "%", format: :json)

      expect(results).to eq([])
    end

    it "caps each type at five results" do
      6.times { |n| create(:user, :verified, first_name: "Zed#{n}", last_name: "Searchable") }

      get admin_search_path(q: "searchable", format: :json)

      expect(results.count { |r| r["type"] == "user" }).to eq(5)
    end
  end

  it "is not available to members" do
    sign_in_via_magic_link(member)

    get admin_search_path(q: "ada", format: :json)

    expect(response).not_to have_http_status(:ok)
    expect(response.body).not_to include("Ada Lovelace")
  end

  it "is not available signed out" do
    get admin_search_path(q: "ada", format: :json)

    expect(response).not_to have_http_status(:ok)
  end
end
