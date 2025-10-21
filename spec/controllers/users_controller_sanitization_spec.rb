# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsersController, type: :controller do
  describe "POST #create" do
    let(:valid_params) do
      {
        user: {
          first_name: "John",
          last_name: "Doe",
          email: "test@example.com",
          password: "validpassword123",
          password_confirmation: "validpassword123"
        }
      }
    end

    context "when first_name contains SQL injection" do
      before do
        allow(NotifyOpsOnSecurityIncidentJob).to receive(:perform_later)
      end

      it "rejects first_name with SELECT statement" do
        params = valid_params.dup
        params[:user][:first_name] = "John'; DROP TABLE users; SELECT * FROM users WHERE '1'='1"
        post :create, params: params
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "notifies ops of SQL injection attempt" do
        params = valid_params.dup
        params[:user][:first_name] = "John'; DROP TABLE users; SELECT * FROM users WHERE '1'='1"
        post :create, params: params
        expect(NotifyOpsOnSecurityIncidentJob).to have_received(:perform_later)
      end

      it "shows invalid input error" do
        params = valid_params.dup
        params[:user][:first_name] = "John'; DROP TABLE users; SELECT * FROM users WHERE '1'='1"
        post :create, params: params
        expect(assigns(:user).errors[:base]).to include(match(/Invalid input/))
      end
    end

    context "when email contains SQL injection" do
      it "rejects email with SQL injection" do
        params = valid_params.dup
        params[:user][:email] = "test@example.com' OR 1=1--"
        post :create, params: params
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "shows invalid input error for email" do
        params = valid_params.dup
        params[:user][:email] = "test@example.com' OR 1=1--"
        post :create, params: params
        expect(assigns(:user).errors[:base]).to include(match(/Invalid input/))
      end
    end

    context "when password contains SQL injection" do
      it "rejects password with SQL injection" do
        params = valid_params.dup
        params[:user][:password] = "password'; DROP TABLE users; --"
        params[:user][:password_confirmation] = "password'; DROP TABLE users; --"
        post :create, params: params
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "shows invalid input error for password" do
        params = valid_params.dup
        params[:user][:password] = "password'; DROP TABLE users; --"
        params[:user][:password_confirmation] = "password'; DROP TABLE users; --"
        post :create, params: params
        expect(assigns(:user).errors[:base]).to include(match(/Invalid input/))
      end
    end

    context "when input contains XSS attempts" do
      let(:xss_params) do
        params = valid_params.dup
        params[:user][:first_name] = "<script>alert('xss')</script>John"
        params
      end

      it "handles first_name with script tags" do
        post :create, params: xss_params
        expect(response.status).to be_in([200, 302, 422])
      end

      it "shows error when rejecting XSS" do
        post :create, params: xss_params
        expect(assigns(:user).errors[:base]).to include(match(/Invalid input/)) if response.status == 422
      end

      it "sanitizes script tags when accepting" do
        post :create, params: xss_params
        expect(assigns(:user).first_name).not_to include("<script>") if response.status != 422
      end
    end

    context "when input exceeds length limits" do
      let(:long_string) { "a" * 1000 }
      let(:long_name_params) do
        params = valid_params.dup
        params[:user][:first_name] = long_string
        params
      end
      let(:long_password_params) do
        params = valid_params.dup
        params[:user][:password] = long_string
        params[:user][:password_confirmation] = long_string
        params
      end

      it "handles very long first_name" do
        post :create, params: long_name_params
        expect(response.status).to be_in([200, 302, 422])
      end

      it "shows error when rejecting long input" do
        post :create, params: long_name_params
        expect(assigns(:user).errors[:base]).to include(match(/Invalid input/)) if response.status == 422
      end

      it "rejects very long password" do
        post :create, params: long_password_params
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "shows error for long password" do
        post :create, params: long_password_params
        expect(assigns(:user).errors[:base]).to include(match(/Invalid input/))
      end
    end

    context "with valid input" do
      it "allows normal signup" do
        post :create, params: valid_params
        expect(response).to have_http_status(:found)
      end
    end
  end
end
