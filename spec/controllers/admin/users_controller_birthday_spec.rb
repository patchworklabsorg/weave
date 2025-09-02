# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::UsersController, type: :controller do
  let(:admin_user) { User.create!(
    first_name: "Admin",
    last_name: "User",
    email: "admin@example.com",
    password: "Password123!",
    password_confirmation: "Password123!",
    role: "admin"
  )}
  
  let(:regular_user) { User.create!(
    first_name: "John",
    last_name: "Doe",
    email: "john@example.com",
    password: "Password123!",
    password_confirmation: "Password123!",
    birthday: Date.parse("1990-01-15")
  )}

  before do
    # Mock admin authentication
    allow(controller).to receive(:current_user).and_return(admin_user)
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:require_admin).and_return(true)
  end

  describe "GET #show" do
    it "displays user birthday when present" do
      get :show, params: { id: regular_user.id }
      expect(response).to have_http_status(:success)
      expect(assigns(:user)).to eq(regular_user)
    end
  end

  describe "PATCH #update" do
    context "when updating birthday as admin" do
      let(:birthday_params) do
        {
          id: regular_user.id,
          user: {
            first_name: regular_user.first_name,
            last_name: regular_user.last_name,
            email: regular_user.email,
            birthday: "1995-05-20"
          }
        }
      end

      it "allows admin to change user birthday" do
        patch :update, params: birthday_params
        expect(response).to have_http_status(:found)
        expect(regular_user.reload.birthday).to eq(Date.parse("1995-05-20"))
        expect(response).to redirect_to(admin_user_path(regular_user))
      end

      it "allows admin to clear user birthday" do
        clear_birthday_params = birthday_params.dup
        clear_birthday_params[:user][:birthday] = ""
        
        patch :update, params: clear_birthday_params
        expect(response).to have_http_status(:found)
        expect(regular_user.reload.birthday).to be_nil
      end

      it "allows admin to set birthday for user without one" do
        user_without_birthday = User.create!(
          first_name: "Jane",
          last_name: "Smith",
          email: "jane@example.com",
          password: "Password123!",
          password_confirmation: "Password123!"
        )

        birthday_params[:id] = user_without_birthday.id
        patch :update, params: birthday_params
        
        expect(response).to have_http_status(:found)
        expect(user_without_birthday.reload.birthday).to eq(Date.parse("1995-05-20"))
      end
    end
  end
end