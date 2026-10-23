# frozen_string_literal: true

FactoryBot.define do
  factory :program_participation do
    user factory: %i[user verified]
    program { "ganymede" }
    year { Date.current.year }
    outcome { "granted" }
    # A funder with no individual-record term, so the row folds at deletion.
    funder { "plain_funder" }

    trait :funder_required do
      funder { "test_funder" }
    end
  end

  factory :grant_disbursement do
    user factory: %i[user verified]
    program { "ganymede" }
    funder { "plain_funder" }
    disbursed_on { Date.current }
    amount_cents { 50_000 }
    currency { "USD" }
    payee_name { "Ada Lovelace" }
    payee_email { "ada@example.com" }
    reference { "PAY-123" }
  end

  factory :deletion_request do
    user factory: %i[user verified]
    source { "member" }

    trait :approved do
      status { "approved" }
      reviewed_by factory: %i[user identity_team]
      reviewed_at { Time.current }
      review_note { "Reply from the address on file." }
    end
  end

  factory :takeout_request do
    user factory: %i[user verified]
    status { "pending" }
  end
end
