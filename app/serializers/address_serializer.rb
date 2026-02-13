# frozen_string_literal: true

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
