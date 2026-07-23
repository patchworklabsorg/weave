# frozen_string_literal: true

require "rails_helper"

RSpec.describe Oauth::UserinfoController, type: :controller do
  let(:user) { create(:user, phone_number: "+18025550123") }

  def stub_token(*scopes)
    token = instance_double(
      Doorkeeper::AccessToken,
      resource_owner_id: user.id,
      scopes: Doorkeeper::OAuth::Scopes.from_array(scopes)
    )
    allow(controller).to receive_messages(doorkeeper_token: token, doorkeeper_authorize!: true)
  end

  describe "GET #show" do
    it "always includes the sub claim" do
      stub_token
      get :show

      json = JSON.parse(response.body)
      expect(json["sub"]).to eq(user.p_id)
    end

    it "includes phone claims when the phone scope is granted" do
      stub_token("phone")
      get :show

      json = JSON.parse(response.body)
      expect(json["phone_number"]).to eq("+18025550123")
      expect(json["phone_number_verified"]).to be(false)
    end

    it "omits phone claims without the phone scope" do
      stub_token("profile")
      get :show

      json = JSON.parse(response.body)
      expect(json).not_to have_key("phone_number")
      expect(json).not_to have_key("phone_number_verified")
    end

    it "includes profile claims when the profile scope is granted" do
      stub_token("profile")
      get :show

      json = JSON.parse(response.body)
      expect(json["name"]).to eq(user.full_name)
      expect(json["preferred_username"]).to eq(user.username)
    end
  end
end
