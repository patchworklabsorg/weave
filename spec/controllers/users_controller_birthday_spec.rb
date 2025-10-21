# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsersController, type: :controller do
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

      it "returns found status when setting birthday" do
        patch :update, params: birthday_params
        expect(response).to have_http_status(:found)
      end

      it "sets the birthday" do
        patch :update, params: birthday_params
        expect(user.reload.birthday).to eq(Date.parse("1990-01-15"))
      end

      context "when birthday is already set" do
        before do
          user.update!(birthday: Date.parse("1990-01-15"))
        end

        let(:change_birthday_params) do
          params = birthday_params.dup
          params[:user][:birthday] = "1995-05-20"
          params
        end

        it "returns found status" do
          patch :update, params: change_birthday_params
          expect(response).to have_http_status(:found)
        end

        it "keeps the original birthday unchanged" do
          patch :update, params: change_birthday_params
          expect(user.reload.birthday).to eq(Date.parse("1990-01-15"))
        end

        it "ignores attempt to clear birthday" do
          clear_birthday_params = birthday_params.dup
          clear_birthday_params[:user][:birthday] = ""
          patch :update, params: clear_birthday_params
          expect(user.reload.birthday).to eq(Date.parse("1990-01-15"))
        end
      end

      it "returns found status for valid date format" do
        patch :update, params: birthday_params
        expect(response).to have_http_status(:found)
      end

      it "stores birthday as Date object" do
        patch :update, params: birthday_params
        expect(user.reload.birthday).to be_a(Date)
      end
    end
  end
end
