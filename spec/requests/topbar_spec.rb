# frozen_string_literal: true

require "rails_helper"

# The member top bar (shared/_topbar): the sections on the left, the account
# menu on the right, and the account tabs on the account pages.
RSpec.describe "Member top bar", type: :request do
  let(:page) { Nokogiri::HTML(response.body) }

  def sections = page.css('nav[aria-label="Sections"] a').map { |link| link.text.strip }
  def tabs = page.css("nav.topbar-tabs a").map { |link| link.text.strip }
  def current_tab = page.at_css('nav.topbar-tabs a[aria-current="page"]')&.text&.strip
  def menu_items = page.css('[role="menu"] [role="menuitem"]').map { |item| item.text.strip }

  it "shows a member one section, the account tabs and a menu with only Sign out" do
    sign_in_via_magic_link(create(:user, :verified))
    get profile_sessions_path

    expect(sections).to eq(["Home", "Account"])
    expect(page.at_css('nav[aria-label="Sections"] a[aria-current="page"]').text.strip).to eq("Account")
    expect(tabs).to eq(["Profile", "Sessions", "Passkeys", "Password", "Social profiles"])
    expect(current_tab).to eq("Sessions")
    expect(menu_items).to eq(["Home", "Account", "Sign out"])
  end

  it "keeps Profile current on a profile page with no tab of its own" do
    sign_in_via_magic_link(create(:user, :verified))
    get edit_profile_path

    expect(current_tab).to eq("Profile")
  end

  it "puts Admin and Verification in the menu, not in the bar" do
    sign_in_via_magic_link(create(:user, :identity_team, :verified))
    get password_path

    expect(current_tab).to eq("Password")
    expect(menu_items).to include("Admin", "Verification", "Sign out")
    expect(page.css(".topbar-end > a.btn")).to be_empty
  end

  it "shows Groups to a manager, without the account tabs on the groups page" do
    manager = create(:user, :verified)
    create(:group_membership, group: create(:group), user: manager, role: "manager")
    sign_in_via_magic_link(manager)
    get groups_path

    expect(sections).to eq(["Home", "Account", "Groups"])
    expect(tabs).to be_empty
  end
end
