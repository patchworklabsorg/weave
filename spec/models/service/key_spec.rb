# frozen_string_literal: true

require "rails_helper"

# == Schema Information
# Schema version: 20261023120000
#
# Table name: service_keys
# Database name: primary
#
#  id             :bigint           not null, primary key
#  api_key_digest :string           not null
#  expires_at     :datetime
#  hash_key       :string           not null
#  last_used_at   :datetime
#  name           :string           not null
#  status         :string           default("active"), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  created_by_id  :bigint           not null
#  service_id     :bigint           not null
#
# Indexes
#
#  index_service_keys_on_api_key_digest         (api_key_digest) UNIQUE
#  index_service_keys_on_created_by_id          (created_by_id)
#  index_service_keys_on_service_id             (service_id)
#  index_service_keys_on_service_id_and_status  (service_id,status)
#  index_service_keys_on_status                 (status)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (service_id => services.id)
#
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
