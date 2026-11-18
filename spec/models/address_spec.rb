# frozen_string_literal: true

# == Schema Information
#
# Table name: addresses
# Database name: primary
#
#  id                              :bigint           not null, primary key
#  address_type                    :enum             default("shipping"), not null
#  addressable_type                :string           not null
#  city_ciphertext                 :text
#  contact_email_ciphertext        :text
#  contact_first_name_ciphertext   :text
#  contact_last_name_ciphertext    :text
#  contact_name_ciphertext         :text
#  contact_phone_number_ciphertext :text
#  country                         :string(2)
#  latitude_ciphertext             :text
#  line1_ciphertext                :text
#  line2_ciphertext                :text
#  line3_ciphertext                :text
#  longitude_ciphertext            :text
#  nickname_ciphertext             :text
#  postal_code_ciphertext          :text
#  residential                     :boolean          default(FALSE), not null
#  shipping_notes_ciphertext       :text
#  state                           :string
#  supports_weekend_deliveries     :boolean          default(FALSE), not null
#  type                            :string           default("Address"), not null
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#  addressable_id                  :bigint           not null
#
# Indexes
#
#  index_addresses_on_addressable                        (addressable_type,addressable_id)
#  index_addresses_on_addressable_id                     (addressable_id)
#  index_addresses_on_addressable_type                   (addressable_type)
#  index_addresses_on_type                               (type)
#  unique_address_per_addressable_type_and_address_type  (addressable_type,addressable_id,type,address_type) UNIQUE
#
require "rails_helper"

RSpec.describe Address, type: :model do
  it "requires city, state, and country" do
    address = described_class.new

    expect(address).not_to be_valid
    expect(address.errors[:city]).to be_present
    expect(address.errors[:state]).to be_present
    expect(address.errors[:country]).to be_present
  end

  it "defines the address_type enum values" do
    expect(described_class.address_types.keys).to include("shipping", "billing")
  end

  describe "encryption at rest" do
    let(:address) do
      create(:shipping_address, line1: "1 Main St", postal_code: "05401", contact_name: "Ada",
                                contact_phone_number: "+18025550100", latitude: 44.47, longitude: -73.21)
    end

    def row = ActiveRecord::Base.connection.select_one("SELECT * FROM addresses WHERE id = #{address.id}")

    it "writes the street, contact and coordinates only as ciphertext" do
      expect(row.keys).not_to include("line1", "postal_code", "contact_name", "contact_phone_number", "latitude", "longitude")
      expect(row["line1_ciphertext"]).to be_present
      expect(row["line1_ciphertext"]).not_to include("Main")
    end

    it "keeps state and country in plain text" do
      expect(row).to include("state" => "IL", "country" => "US")
    end

    it "reads the values back" do
      expect(described_class.find(address.id)).to have_attributes(line1: "1 Main St", postal_code: "05401",
                                                                  latitude: 44.47, longitude: -73.21)
    end
  end
end
