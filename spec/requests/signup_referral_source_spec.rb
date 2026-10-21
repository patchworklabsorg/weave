# frozen_string_literal: true

require "rails_helper"

# The signup form asks how the person found Patchwork. The answer is optional.
RSpec.describe "Signup referral source", type: :request do
  def sign_up(**referral)
    post signup_path, params: { user: { first_name: "Ada", last_name: "Lovelace", email: "ada@example.com", birthday: "1990-12-10", **referral } }
  end

  it "shows the question on the signup form" do
    get signup_path

    expect(response.body).to include("How did you hear about Patchwork?")
  end

  it "saves the source and the detail" do
    sign_up(referral_source: "event", referral_source_detail: "  Boston Hacks  ")

    user = User.find_by!(email: "ada@example.com")
    expect(user.referral_source).to eq("event")
    expect(user.referral_source_detail).to eq("Boston Hacks")
  end

  it "lets the person skip the question" do
    expect { sign_up(referral_source: "", referral_source_detail: "") }.to change(User, :count).by(1)

    user = User.find_by!(email: "ada@example.com")
    expect(user.referral_source).to be_nil
    expect(user.referral_source_detail).to be_nil
  end

  it "refuses a source that is not on the list" do
    expect { sign_up(referral_source: "carrier_pigeon") }.not_to change(User, :count)

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "does not let a member change the answer from the profile form" do
    user = create(:user, :verified)
    sign_in_via_magic_link(user)

    patch update_profile_path, params: { user: { first_name: user.first_name, referral_source: "search" } }

    expect(user.reload.referral_source).to be_nil
  end

  it "shows the answer to an admin" do
    member = create(:user, :verified, referral_source: "friend", referral_source_detail: "Jo")
    sign_in_via_magic_link(create(:user, :admin, :verified))

    get admin_user_path(member)

    expect(response.body).to include("A friend or member: Jo")
  end
end
