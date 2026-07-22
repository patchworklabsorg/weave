# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AuthController#check_password_login", type: :request do
  it "enables password login for admins" do
    create(:user, :admin, email: "admin@example.com")

    post "/auth/check_password_login", params: { email: "admin@example.com" }, as: :json

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["password_login_enabled"]).to be(true)
    expect(body["password_required"]).to be(true)
  end

  it "does not enable password login for regular users" do
    create(:user, email: "regular@example.com")

    post "/auth/check_password_login", params: { email: "regular@example.com" }, as: :json

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["password_login_enabled"]).to be(false)
  end

  it "returns ok without leaking existence for unknown emails" do
    post "/auth/check_password_login", params: { email: "nobody@example.com" }, as: :json

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["password_login_enabled"]).to be(false)
  end
end
