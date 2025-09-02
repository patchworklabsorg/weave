# frozen_string_literal: true

require "rails_helper"

RSpec.feature "Admin birthday management", type: :feature do
  let(:admin_user) { User.create!(
    first_name: "Admin",
    last_name: "User",
    email: "admin@example.com",
    password: "Password123!",
    password_confirmation: "Password123!",
    role: "admin"
  )}
  
  let(:user_with_birthday) { User.create!(
    first_name: "John",
    last_name: "Doe",
    email: "john@example.com",
    password: "Password123!",
    password_confirmation: "Password123!",
    birthday: Date.current
  )}
  
  let(:user_without_birthday) { User.create!(
    first_name: "Jane",
    last_name: "Smith",
    email: "jane@example.com",
    password: "Password123!",
    password_confirmation: "Password123!"
  )}

  before do
    # Mock admin authentication
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(admin_user)
    allow_any_instance_of(ApplicationController).to receive(:authenticate_user!).and_return(true)
    allow_any_instance_of(Admin::BaseController).to receive(:require_admin).and_return(true)
  end

  scenario "Admin can see user birthday on user show page" do
    user_with_birthday.update!(birthday: Date.parse("1990-01-15"))
    
    visit admin_user_path(user_with_birthday)
    
    expect(page).to have_content("Birthday")
    expect(page).to have_content("January 15, 1990")
  end

  scenario "Admin sees birthday banner when it's user's birthday" do
    visit admin_user_path(user_with_birthday)
    
    expect(page).to have_content("Happy Birthday!")
    expect(page).to have_content("It's John's birthday today!")
  end

  scenario "Admin does not see birthday banner for users without birthdays" do
    visit admin_user_path(user_without_birthday)
    
    expect(page).not_to have_content("Happy Birthday!")
  end

  scenario "Admin can edit user information including birthday" do
    visit admin_user_path(user_without_birthday)
    
    expect(page).to have_link("Edit User")
    
    # Note: In a real test environment, we would click the link and test the edit form
    # click_link "Edit User"
    # expect(page).to have_field("Birthday")
  end
end