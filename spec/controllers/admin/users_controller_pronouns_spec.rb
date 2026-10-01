# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::UsersController, type: :controller do
  let(:admin_user) {
    User.create!(
      first_name: "Admin",
      last_name: "User",
      email: "admin@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      role: "admin"
    )
  }

  let(:regular_user) {
    User.create!(
      first_name: "John",
      last_name: "Doe",
      email: "john@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      pronouns: "she/her"
    )
  }

  before do
    # Mock admin authentication
    allow(controller).to receive_messages(current_user: admin_user, authenticate_user!: true, require_admin: true, track_user_session: true)
  end

  describe "PATCH #update" do
    context "when updating pronouns as admin" do
      let(:pronouns_params) do
        {
          id: regular_user.to_param,
          user: {
            first_name: regular_user.first_name,
            last_name: regular_user.last_name,
            email: regular_user.email,
            pronouns: "they/them"
          }
        }
      end

      it "returns found status when updating pronouns" do
        patch :update, params: pronouns_params
        expect(response).to have_http_status(:found)
      end

      it "changes the user pronouns" do
        patch :update, params: pronouns_params
        expect(regular_user.reload.pronouns).to eq("they/them")
      end

      it "redirects to admin user path after updating" do
        patch :update, params: pronouns_params
        expect(response).to redirect_to(admin_user_path(regular_user))
      end

      it "clears the user pronouns when submitted blank" do
        clear_pronouns_params = pronouns_params.dup
        clear_pronouns_params[:user][:pronouns] = ""

        patch :update, params: clear_pronouns_params
        expect(regular_user.reload.pronouns).to be_nil
      end
    end
  end
end
