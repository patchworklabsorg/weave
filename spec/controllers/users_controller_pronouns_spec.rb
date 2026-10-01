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
    context "when updating pronouns" do
      let(:pronouns_params) do
        {
          user: {
            first_name: user.first_name,
            last_name: user.last_name,
            email: user.email,
            pronouns: "they/them"
          }
        }
      end

      it "returns found status when setting pronouns" do
        patch :update, params: pronouns_params
        expect(response).to have_http_status(:found)
      end

      it "sets the pronouns" do
        patch :update, params: pronouns_params
        expect(user.reload.pronouns).to eq("they/them")
      end

      it "strips surrounding whitespace" do
        params = pronouns_params.dup
        params[:user][:pronouns] = "  she/her  "
        patch :update, params: params
        expect(user.reload.pronouns).to eq("she/her")
      end

      context "when pronouns are already set" do
        before do
          user.update!(pronouns: "they/them")
        end

        it "updates to new pronouns" do
          params = pronouns_params.dup
          params[:user][:pronouns] = "he/him"
          patch :update, params: params
          expect(user.reload.pronouns).to eq("he/him")
        end

        it "clears pronouns when submitted blank" do
          params = pronouns_params.dup
          params[:user][:pronouns] = ""
          patch :update, params: params
          expect(user.reload.pronouns).to be_nil
        end
      end
    end
  end
end
