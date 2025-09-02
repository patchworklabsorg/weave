# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsersController, type: :controller do
  let(:user) { User.create!(
    first_name: "John",
    last_name: "Doe",
    email: "john@example.com",
    password: "Password123!",
    password_confirmation: "Password123!"
  )}

  before do
    sign_in user
  end

  describe "PATCH #update" do
    context "when updating birthday" do
      let(:birthday_params) do
        {
          user: {
            first_name: user.first_name,
            last_name: user.last_name,
            email: user.email,
            birthday: "1990-01-15"
          }
        }
      end

      it "allows setting a birthday initially" do
        patch :update, params: birthday_params
        expect(response).to have_http_status(:found)
        expect(user.reload.birthday).to eq(Date.parse("1990-01-15"))
      end

      it "prevents changing birthday once it's set" do
        user.update!(birthday: Date.parse("1990-01-15"))
        
        change_birthday_params = birthday_params.dup
        change_birthday_params[:user][:birthday] = "1995-05-20"
        
        patch :update, params: change_birthday_params
        expect(response).to have_http_status(:found)
        # Birthday should remain unchanged
        expect(user.reload.birthday).to eq(Date.parse("1990-01-15"))
      end

      it "ignores birthday parameter when already set" do
        user.update!(birthday: Date.parse("1990-01-15"))
        
        # Try to clear birthday (should be ignored)
        clear_birthday_params = birthday_params.dup
        clear_birthday_params[:user][:birthday] = ""
        
        patch :update, params: clear_birthday_params
        expect(response).to have_http_status(:found)
        # Birthday should remain unchanged
        expect(user.reload.birthday).to eq(Date.parse("1990-01-15"))
      end

      it "accepts valid date formats for initial setting" do
        patch :update, params: birthday_params
        expect(response).to have_http_status(:found)
        expect(user.reload.birthday).to be_a(Date)
      end
    end
  end
end