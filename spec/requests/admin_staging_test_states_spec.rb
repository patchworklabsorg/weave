# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin staging test states", type: :request do
  let(:owner) { create(:user, :owner, :verified) }
  let(:member) { create(:user, :verified) }

  it "lets an owner on staging set a test state from the user page" do
    allow(Weave).to receive(:staging?).and_return(true)
    sign_in_via_magic_link(owner)

    get admin_user_path(member)
    expect(response.body).to include("Staging test states")

    patch admin_user_staging_test_state_path(member), params: { area: "identity", state: "verified" }

    expect(response).to redirect_to(admin_user_path(member))
    expect(flash[:notice]).to eq("The test state is set: Passed.")
    expect(member.reload.verification_status).to eq("verified")
  end

  it "does not exist outside staging" do
    sign_in_via_magic_link(owner)

    get admin_user_path(member)
    expect(response.body).not_to include("Staging test states")

    patch admin_user_staging_test_state_path(member), params: { area: "identity", state: "verified" }

    expect(response).to have_http_status(:not_found)
    expect(member.reload.verifications).to be_empty
  end
end
