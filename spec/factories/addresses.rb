# frozen_string_literal: true

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
