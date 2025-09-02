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

  scenario "User can set birthday initially but not change it" do
    # First visit - should show birthday field
    visit edit_profile_path
    
    expect(page).to have_field("Birthday")
    expect(page).to have_content("Birthday can only be set once")
    
    # Simulate setting birthday (in real app this would submit form)
    user.update!(birthday: Date.parse("1990-01-15"))
    
    # Second visit - should show read-only birthday
    visit edit_profile_path
    
    expect(page).not_to have_field("Birthday")
    expect(page).to have_content("January 15, 1990")
    expect(page).to have_content("Birthday cannot be changed")
  end
end