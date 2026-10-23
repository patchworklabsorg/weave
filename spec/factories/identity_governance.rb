# frozen_string_literal: true

FactoryBot.define do
  factory :identity_governance_proposal do
    kind { "add_member" }
    subject factory: %i[user verified]
    proposed_by factory: %i[user owner verified]
    reason { "Runs the Ganymede calls." }
    expires_at { 14.days.from_now }
  end
end
