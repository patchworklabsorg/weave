# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Profile legal name", type: :request do
  let(:user) { create(:user, :verified, first_name: "John", last_name: "Doe") }

  it "updates the legal name separately from the preferred name" do
    sign_in_via_magic_link(user)

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
    sign_in_via_magic_link(user)

    patch update_profile_path, params: {
      user: { legal_first_name: "", legal_last_name: "" }
    }

    user.reload
    expect(user.legal_first_name).to be_nil
    expect(user.legal_last_name).to be_nil
  end

  it "does not let a user change another user's legal name" do
    other = create(:user, :verified, legal_first_name: "Alex", legal_last_name: "Rivera")
    sign_in_via_magic_link(user)

    patch update_profile_path, params: {
      id: other.id,
      user: { id: other.id, legal_first_name: "Changed", legal_last_name: "Changed" }
    }

    expect(other.reload).to have_attributes(legal_first_name: "Alex", legal_last_name: "Rivera")
    expect(user.reload).to have_attributes(legal_first_name: "Changed", legal_last_name: "Changed")
  end
end
