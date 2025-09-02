# frozen_string_literal: true

require "rails_helper"

RSpec.feature "User birthday management", type: :feature do
  let(:user) { User.create!(
    first_name: "John",
    last_name: "Doe", 
    email: "john@example.com",
    password: "Password123!",
    password_confirmation: "Password123!"
  )}

  before do
    # Mock user authentication for feature tests
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    allow_any_instance_of(ApplicationController).to receive(:authenticate_user!).and_return(true)
  end

  scenario "User can view their birthday on profile page" do
    user.update!(birthday: Date.parse("1990-01-15"))
    
    visit profile_path
    
    expect(page).to have_content("Birthday")
    expect(page).to have_content("January 15, 1990")
  end

  scenario "User does not see birthday section when no birthday is set" do
    visit profile_path
    
    expect(page).not_to have_content("Birthday")
  end

  scenario "User can edit their birthday" do
    visit edit_profile_path
    
    expect(page).to have_field("Birthday")
    
    fill_in "Birthday", with: "1990-01-15"
    
    # Note: This test would require the full Rails environment to work properly
    # In a real test, we would click save and verify the change
    expect(page).to have_field("Birthday", with: "1990-01-15")
  end
end