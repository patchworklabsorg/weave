# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserSerializer do
  let(:user) do
    create(:user, first_name: "John", last_name: "Doe", legal_first_name: "Jonathan", legal_last_name: "Dorian")
  end

  it "uses the preferred name" do
    expect(described_class.render(user)).to include(first_name: "John", last_name: "Doe", full_name: "John Doe")
  end

  it "leaves the legal name out" do
    json = described_class.render(user, include_addresses: true)

    expect(json.keys.map(&:to_s)).not_to include(a_string_matching(/legal/))
    expect(json.to_json).not_to include("Jonathan", "Dorian")
  end
end
