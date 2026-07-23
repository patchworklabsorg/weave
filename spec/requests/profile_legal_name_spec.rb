# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Profile legal name", type: :request do
  # Log in through the real magic-link flow so complete_login establishes a
  # validatable user_sessions record for the cookie.
  def login(user)
    token = SecureRandom.urlsafe_base64(32)
    user.update!(
      magic_link_token: token,
      magic_link_expires_at: 15.minutes.from_now,
      magic_link_used_at: nil
    )
    get magic_link_login_path(token: token)
  end

  let(:user) { create(:user, :verified, first_name: "John", last_name: "Doe") }

  it "updates the legal name separately from the preferred name" do
    login(user)

    patch update_profile_path, params: {
      user: {
        first_name: "John",
        last_name: "Doe",
        legal_first_name: "Jonathan",
        legal_last_name: "Dorian"
      }
    }

    expect(response).to redirect_to(root_path)
    user.reload
    expect(user.first_name).to eq("John")
    expect(user.last_name).to eq("Doe")
    expect(user.legal_first_name).to eq("Jonathan")
    expect(user.legal_last_name).to eq("Dorian")
  end

  it "clears the legal name when submitted blank" do
    user.update!(legal_first_name: "Jonathan", legal_last_name: "Dorian")
    login(user)

    patch update_profile_path, params: {
      user: { legal_first_name: "", legal_last_name: "" }
    }

    user.reload
    expect(user.legal_first_name).to be_nil
    expect(user.legal_last_name).to be_nil
  end
end
