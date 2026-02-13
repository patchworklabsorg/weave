# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    first_name { "John" }
    last_name { "Doe" }
    password { "SecurePassword123!" }
    password_confirmation { "SecurePassword123!" }
    role { :user }
    status { "active" }

    trait :admin do
      role { :admin }
    end

    trait :superadmin do
      role { :superadmin }
    end

    trait :owner do
      role { :owner }
    end

    trait :verified do
      email_confirmed_at { Time.current }
    end

    trait :unverified do
      email_confirmed_at { nil }
    end

    trait :with_magic_link do
      magic_link_token { SecureRandom.urlsafe_base64(32) }
      magic_link_expires_at { 15.minutes.from_now }
      magic_link_sent_at { Time.current }
      magic_link_used_at { nil }
    end
  end
end
