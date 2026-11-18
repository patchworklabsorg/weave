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
class AddressSerializer
  def initialize(address)
    @address = address
  end

  def as_json
    {
      id: @address.public_id,
      address_type: @address.address_type,
      line1: @address.line1,
      line2: @address.line2,
      line3: @address.line3,
      city: @address.city,
      state: @address.state,
      postal_code: @address.postal_code,
      # The ISO 3166 code. Address#country gives a country object.
      country: @address[:country],
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
