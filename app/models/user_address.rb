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
class UserAddress < Address
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :addr

  # Additional validations specific to user addresses
  validates :addressable_type, inclusion: { in: ["User"] }

  # We could add more restrictive address type validation here if needed
  # For now, relying on the base Address model's enum validation

  # User-specific methods
  def user
    addressable
  end

  # Override to provide user-specific validation messages
  def self.human_attribute_name(attr, options = {})
    case attr.to_s
    when "addressable"
      "User"
    else
      super
    end
  end

end
