# frozen_string_literal: true

require "rails_helper"

# The sidebar of the admin and identity layout (see AdminNavHelper): four
# headed groups, and each role sees only what it can use.
RSpec.describe "Admin sidebar", type: :request do
  def sidebar
    nav = Nokogiri::HTML(response.body).at_css('aside[aria-label="Admin navigation"] nav.sidebar-nav')
    nav.css(".nav-section").to_h do |group|
      [group.at_css(".nav-section-title").text.strip, group.css("a.nav-link").map { |link| link.text.strip }]
    end
  end

  def current_link = Nokogiri::HTML(response.body).at_css('aside[aria-label="Admin navigation"] nav.sidebar-nav a[aria-current="page"]')&.text&.strip

  it "shows a verifier without the admin role only the Identity group" do
    sign_in_via_magic_link(create(:user, :verified, identity_team: true))

    get identity_verifications_path

    expect(sidebar).to eq("Identity" => ["Verification", "US residency", "Key custody"])
    expect(current_link).to eq("Verification")
    expect(response.body).to include("Sign out", "Back to Weave")
  end

  it "shows an admin outside the identity team People, Data and System, without Deletion" do
    sign_in_via_magic_link(create(:user, :admin, :verified))

    get admin_root_path

    expect(sidebar).to eq(
      "People" => ["Users", "Staff and contractors", "Groups", "Patches", "Consents"],
      "Data"   => ["Demographics", "Funder reports"],
      "System" => ["Dashboard", "OAuth apps", "Services", "Jobs", "Feature flags", "Blazer", "Console audits", "Console sign-in"]
    )
    expect(current_link).to eq("Dashboard")
  end

  it "shows an identity team admin every group, with Deletion and the Knot" do
    sign_in_via_magic_link(create(:user, :identity_team, :verified))

    get admin_users_path

    expect(sidebar).to eq(
      "Identity" => ["Verification", "US residency", "Key custody", "Knot"],
      "People"   => ["Users", "Staff and contractors", "Groups", "Patches", "Consents"],
      "Data"     => ["Deletion", "Demographics", "Funder reports"],
      "System"   => ["Dashboard", "OAuth apps", "Services", "Jobs", "Feature flags", "Blazer", "Console audits", "Console sign-in"]
    )
    expect(current_link).to eq("Users")
  end

  it "shows an owner key custody and governance in Identity" do
    sign_in_via_magic_link(create(:user, :owner, :verified))

    get identity_governance_path

    expect(sidebar["Identity"]).to eq(["Key custody", "Governance"])
    expect(sidebar.keys).to eq(%w[Identity People Data System])
    expect(current_link).to eq("Governance")
  end

  it "shows a board member without the admin role only key custody and governance" do
    sign_in_via_magic_link(create(:user, :verified, :board))

    get identity_key_custody_path

    expect(sidebar).to eq("Identity" => ["Key custody", "Governance"])
    expect(current_link).to eq("Key custody")
  end

  it "points a verifier who is not an admin home to the identity area, not the admin dashboard" do
    sign_in_via_magic_link(create(:user, :verified, identity_team: true))

    get identity_verifications_path

    page = Nokogiri::HTML(response.body)
    expect(page.css("a").map { |link| link["href"] }).not_to include(admin_root_path)
    expect(page.at_css(".admin-topbar-crumb a")["href"]).to eq(identity_verifications_path)
  end

  it "shows no identity links while an admin impersonates a verifier" do
    sign_in_via_magic_link(create(:user, :owner, :verified))
    post impersonate_admin_user_path(create(:user, :verified, identity_team: true))

    get profile_path

    expect(response.body).not_to include(identity_verifications_path, identity_governance_path)
  end

  def crumbs = Nokogiri::HTML(response.body).css(".admin-topbar-crumb a, .admin-topbar-crumb strong").map { |node| node.text.strip }

  it "puts the section in the top bar crumbs of a page under it" do
    sign_in_via_magic_link(create(:user, :admin, :verified))
    application = Doorkeeper::Application.create!(name: "Quilt Staging", redirect_uri: "https://quilt.example.com/cb", scopes: "profile")

    get admin_oauth_application_path(application)

    expect(crumbs).to eq(["Admin", "OAuth apps", "Quilt Staging"])
    expect(Nokogiri::HTML(response.body).at_css(".admin-topbar-crumb a[href='#{admin_oauth_applications_path}']")).to be_present
  end

  it "leaves the section out of the crumbs on the section's own page" do
    sign_in_via_magic_link(create(:user, :admin, :verified))

    get admin_oauth_applications_path

    expect(crumbs).to eq(["Admin", "OAuth apps"])
    expect(Nokogiri::HTML(response.body).at_css(".admin-topbar-crumb a[href='#{admin_oauth_applications_path}']")).to be_nil
  end

  it "highlights the group link for a page under it" do
    sign_in_via_magic_link(create(:user, :identity_team, :verified))

    get identity_break_glass_records_path

    expect(current_link).to eq("Verification")
  end
end
