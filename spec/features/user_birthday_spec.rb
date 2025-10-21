# frozen_string_literal: true

require "rails_helper"

RSpec.feature "User birthday management", type: :feature do
  let(:user) {
    User.create!(
      first_name: "John",
      last_name: "Doe",
      email: "john@example.com",
      password: "Password123!",
      password_confirmation: "Password123!"
    )
  }

  before do
    # Sign in as user
    sign_in user
  end

  scenario "User views birthday label on profile page" do
    user.update!(birthday: Date.parse("1990-01-15"))
    visit profile_path
    expect(page).to have_content("Birthday")
  end

  scenario "User sees formatted birthday date" do
    user.update!(birthday: Date.parse("1990-01-15"))
    visit profile_path
    expect(page).to have_content("January 15, 1990")
  end

  scenario "User does not see birthday section when no birthday is set" do
    visit profile_path
    expect(page).not_to have_content("Birthday")
  end

  scenario "User sees birthday field when no birthday is set" do
    visit edit_profile_path
    expect(page).to have_field("Birthday")
  end

  scenario "User sees birthday warning message" do
    visit edit_profile_path
    expect(page).to have_content("Birthday can only be set once")
  end

  scenario "User cannot edit birthday field once set" do
    user.update!(birthday: Date.parse("1990-01-15"))
    visit edit_profile_path
    expect(page).not_to have_field("Birthday")
  end

  scenario "User sees birthday value when set" do
    user.update!(birthday: Date.parse("1990-01-15"))
    visit edit_profile_path
    expect(page).to have_content("January 15, 1990")
  end

  scenario "User sees birthday cannot be changed message" do
    user.update!(birthday: Date.parse("1990-01-15"))
    visit edit_profile_path
    expect(page).to have_content("Birthday cannot be changed")
  end
end
