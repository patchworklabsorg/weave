# frozen_string_literal: true

# == Schema Information
#
# Table name: knots
# Database name: primary
#
#  id          :bigint           not null, primary key
#  blacklisted :boolean          default(FALSE), not null
#  user_id     :bigint
#
# Indexes
#
#  index_knots_on_user_id  (user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
FactoryBot.define do
  factory :knot do
    user factory: %i[user verified]
    blacklisted { false }

    trait :detached do
      user { nil }
    end

    trait :blacklisted do
      blacklisted { true }
    end

    # A passed attempt linked to the Knot, to hold the audit rows of changes.
    trait :with_audit do
      after(:create) do |knot|
        create(:verification, :verified, user: knot.user, knot:)
      end
    end
  end

  factory :knot_hash do
    knot
    kind { "soft" }
    sequence(:digest) { |n| OpenSSL::Digest::SHA256.hexdigest("knot hash #{n}") }
  end

  factory :knot_change_request do
    knot factory: %i[knot with_audit]
    verification { knot.audit_verification }
    requested_by factory: %i[user identity_team]
    kind { "set_blacklist" }
  end

  factory :program_grant do
    knot
    program { "ganymede" }
    granted_at { 1.month.ago }
  end
end
