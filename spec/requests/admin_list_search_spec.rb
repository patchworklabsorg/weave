# frozen_string_literal: true

require "rails_helper"

# Every admin list has a search box that reloads its Turbo frame.
RSpec.describe "Admin list search", type: :request do
  let(:admin) { create(:user, :admin, :verified) }

  before { sign_in_via_magic_link(admin) }

  describe "groups" do
    let!(:engineering) { create(:group, name: "Engineering", slug: "eng", description: "Builds things") }
    let!(:finance) { create(:group, name: "Finance", slug: "fin", description: "Counts things") }

    it "filters by name, slug or description" do
      get admin_groups_path(search: "eng")
      expect(response.body).to include("Engineering")
      expect(response.body).not_to include("Finance")

      get admin_groups_path(search: "counts")
      expect(response.body).to include("Finance")
      expect(response.body).not_to include("Engineering")
    end

    it "says when nothing matches" do
      get admin_groups_path(search: "zzz")
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Engineering")
      expect(response.body).to include("zzz")
    end
  end

  describe "group members" do
    let!(:group) { create(:group, name: "Engineering", slug: "eng") }
    let!(:ada) { create(:user, :verified, first_name: "Ada", last_name: "Lovelace", email: "ada@example.com") }
    let!(:grace) { create(:user, :verified, first_name: "Grace", last_name: "Hopper", email: "grace@example.com") }

    before do
      create(:group_membership, group: group, user: ada)
      create(:group_membership, group: group, user: grace)
    end

    it "filters members by name or email" do
      get admin_group_path(group, search: "hopper")
      expect(response.body).to include("grace@example.com")
      expect(response.body).not_to include("ada@example.com")
    end
  end

  describe "OAuth apps" do
    let!(:krater) { Doorkeeper::Application.create!(name: "Krater", redirect_uri: "https://krater.example.com/cb", scopes: "profile") }
    let!(:quilt) { Doorkeeper::Application.create!(name: "Quilt", redirect_uri: "https://quilt.example.com/cb", scopes: "profile") }

    it "filters by name, client id or redirect URI" do
      get admin_oauth_applications_path(search: "krat")
      expect(response.body).to include("Krater")
      expect(response.body).not_to include(">Quilt<")

      get admin_oauth_applications_path(search: quilt.uid)
      expect(response.body).to include("Quilt")
      expect(response.body).not_to include(">Krater<")
    end
  end
end
