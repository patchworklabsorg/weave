# frozen_string_literal: true

# == Schema Information
#
# Table name: email_addresses
# Database name: primary
#
#  id                   :bigint           not null, primary key
#  confirmation_sent_at :datetime
#  confirmation_token   :string
#  confirmed_at         :datetime
#  email                :string           not null
#  is_primary           :boolean          default(FALSE), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  user_id              :bigint           not null
#
# Indexes
#
#  index_email_addresses_on_confirmation_token  (confirmation_token) UNIQUE
#  index_email_addresses_on_email               (email) UNIQUE
#  index_email_addresses_on_user_id             (user_id)
#  index_email_addresses_one_primary_per_user   (user_id) UNIQUE WHERE is_primary
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :email_address do
    user
    sequence(:email) { |n| "extra#{n}@example.com" }
    is_primary { false }

    trait :confirmed do
      confirmed_at { Time.current }
    end

    trait :with_confirmation_token do
      confirmation_token { SecureRandom.urlsafe_base64(32) }
      confirmation_sent_at { Time.current }
    end
  end
end
