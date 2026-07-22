# frozen_string_literal: true

# == Schema Information
#
# Table name: addresses
# Database name: primary
#
#  id                          :bigint           not null, primary key
#  address_type                :enum             default("shipping"), not null
#  addressable_type            :string           not null
#  city                        :string
#  contact_email               :string
#  contact_first_name          :string
#  contact_last_name           :string
#  contact_name                :string
#  contact_phone_number        :string
#  country                     :string(2)
#  latitude                    :float
#  line1                       :string
#  line2                       :string
#  line3                       :string
#  longitude                   :float
#  nickname                    :string
#  postal_code                 :string
#  residential                 :boolean          default(FALSE), not null
#  shipping_notes              :text
#  state                       :string
#  supports_weekend_deliveries :boolean          default(FALSE), not null
#  type                        :string           default("Address"), not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  addressable_id              :bigint           not null
#
# Indexes
#
#  index_addresses_on_addressable                        (addressable_type,addressable_id)
#  index_addresses_on_addressable_id                     (addressable_id)
#  index_addresses_on_addressable_type                   (addressable_type)
#  index_addresses_on_type                               (type)
#  unique_address_per_addressable_type_and_address_type  (addressable_type,addressable_id,type,address_type) UNIQUE
#
class AddressSerializer
  def initialize(address)
    @address = address
  end

  def as_json
    {
      id: @address.id,
      address_type: @address.address_type,
      street_address: @address.street_address,
      street_address_2: @address.street_address_2,
      city: @address.city,
      state: @address.state,
      postal_code: @address.postal_code,
      country: @address.country,
      latitude: @address.latitude,
      longitude: @address.longitude
    }
  end

  def to_json(*args)
    as_json.to_json(*args)
  end

  class << self
    def render(address)
      new(address).as_json
    end

    def render_collection(addresses)
      addresses.map { |address| new(address).as_json }
    end

  end

end
