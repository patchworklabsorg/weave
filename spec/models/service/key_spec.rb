# frozen_string_literal: true

require "rails_helper"

RSpec.describe Service::Key do
  it "makes its hash key on create, before the presence check" do
    key = described_class.create!(service: create(:service), name: "Primary", created_by: create(:user, :admin),
                                  api_key: described_class.generate_api_key)

    expect(key.hash_key).to be_present
  end

  it "is found by the raw key, which it does not store" do
    key = create(:service_key)

    # find_by_api_key is a real method that digests the key, not a dynamic finder.
    expect(described_class.find_by_api_key(key.api_key)).to eq(key) # rubocop:disable Rails/DynamicFindBy
    expect(described_class.find_by_api_key("pwl_wrong")).to be_nil # rubocop:disable Rails/DynamicFindBy
    expect(described_class.column_names).not_to include("api_key")
  end

  it "keeps its usages" do
    key = create(:service_key)
    key.usages.create!(request_path: "/api/v1/health", request_method: "GET")

    expect(key.usages.count).to eq(1)
  end
end
