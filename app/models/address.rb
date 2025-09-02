# frozen_string_literal: true

class Address < ApplicationRecord
  belongs_to :addressable, polymorphic: true, inverse_of: :addresses
  attribute :allow_partial_address, :boolean, default: false

  validates :city, :country, presence: true
  validates :line1, :postal_code, presence: true, if: -> { !allow_partial_address }
  validates :supports_weekend_deliveries, :residential, inclusion: [true, false]

  validates :contact_email, email: true, allow_nil: true
  validates :contact_phone_number, phone: true, allow_nil: true

  enum :address_type, {
  venue: 'Venue',
    shipping: 'Shipping',
    loading_dock: 'Loading Dock'
  }

  PARAMS = [:nickname, :contact_first_name, :contact_last_name, :contact_email, :contact_phone_number, :line1, :line2,
            :line3, :city, :state, :postal_code, :country, :latitude, :longitude, :residential,
            :supports_weekend_deliveries, :allow_partial_address].freeze

  def complete?
    line1? && city? && country? && postal_code?
  end

  def incomplete?
    !complete?
  end

  def country
    ISO3166::Country.new(self[:country])
  end

  def self.ransackable_attributes(_auth_object = nil)
    ['id', 'nickname', 'line1', 'line2', 'line3']
  end

  private

  def parse_phone
    return if self[:contact_phone_number].nil?

    parsed = Phonelib.parse self[:contact_phone_number]

    self[:contact_phone_number] = parsed.full_e164
  end
end
