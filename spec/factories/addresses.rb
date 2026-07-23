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
FactoryBot.define do
  factory :address do
    association :addressable, factory: :user
    street_address { "123 Main St" }
    street_address_2 { nil }
    city { "Springfield" }
    state { "IL" }
    postal_code { "62701" }
    country { "US" }
    address_type { "UserAddress" }

    factory :shipping_address, class: "ShippingAddress" do
      address_type { "Shipping" }
    end

    factory :billing_address, class: "BillingAddress" do
      address_type { "Billing" }
    end
  end
end
