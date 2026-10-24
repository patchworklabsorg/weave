# frozen_string_literal: true

FactoryBot.define do
  factory :identity_nda do
    user factory: %i[user verified]
    signed_on { 1.week.ago.to_date }
    nda_version { "2026-10" }
    sequence(:signature_reference) { |n| "Adobe agreement #{n}" }
    recorded_by factory: %i[user owner verified]
  end

  factory :identity_governance_proposal do
    kind { "add_member" }
    subject factory: %i[user verified]
    proposed_by factory: %i[user owner verified]
    reason { "Runs the Ganymede calls." }
    expires_at { 14.days.from_now }
  end
end
