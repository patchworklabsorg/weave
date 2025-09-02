# frozen_string_literal: true

# == Schema Information
#
# Table name: addresses
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
class Address < ApplicationRecord
  belongs_to :addressable, polymorphic: true, inverse_of: :addresses
  attribute :allow_partial_address, :boolean, default: false

  # STI configuration
  self.inheritance_column = "type"

  # Standard address field validations
  validates :line1, presence: true, unless: :allow_partial_address
  validates :city, presence: true
  validates :state, presence: true
  validates :postal_code, presence: true, unless: :allow_partial_address
  validates :country, presence: true

  # Contact field validations
  validates :contact_name, presence: true, if: -> { contact_email.present? || contact_phone_number.present? }
  validates_email_format_of :contact_email, allow_nil: true
  validate :validate_phone_number, if: -> { contact_phone_number.present? }

  # Boolean field validations
  validates :supports_weekend_deliveries, :residential, inclusion: [true, false]

  # Uniqueness constraint on addressable + type + address_type
  validates :address_type, uniqueness: {
    scope: [:addressable_type, :addressable_id, :type],
    message: "already exists for this addressable entity"
  }

  # Phone number parsing callback
  before_save :parse_phone_number

  enum :address_type, {
    venue: "Venue",
    shipping: "Shipping",
    loading_dock: "Loading Dock",
    billing: "Billing"
  }

  PARAMS = [:nickname, :contact_name, :contact_first_name, :contact_last_name, :contact_email, :contact_phone_number, :line1, :line2,
            :line3, :city, :state, :postal_code, :country, :latitude, :longitude, :residential,
            :supports_weekend_deliveries, :allow_partial_address, :shipping_notes].freeze

  def complete?
    line1? && city? && country? && postal_code?
  end

  def incomplete?
    !complete?
  end

  def country
    return nil if self[:country].blank?

    ISO3166::Country[self[:country]]
  end

  def country_name
    country&.common_name || country&.iso_short_name
  end

  def self.ransackable_attributes(_auth_object = nil)
    ["id", "nickname", "line1", "line2", "line3"]
  end

  private

  def validate_phone_number
    return if contact_phone_number.blank?

    # Parse phone number with country context if available
    country_code = country.present? ? self[:country] : nil
    parsed = Phonelib.parse(contact_phone_number, country_code)

    return if parsed.valid?

    errors.add(:contact_phone_number, "is not a valid phone number")

  end

  def parse_phone_number
    return if contact_phone_number.blank?

    # Parse phone number with country context if available
    country_code = self[:country].presence
    parsed = Phonelib.parse(contact_phone_number, country_code)

    return unless parsed.valid?

    self.contact_phone_number = parsed.full_e164

  end

end
