# frozen_string_literal: true

# == Schema Information
#
# Table name: verifications
# Database name: primary
#
#  id                        :bigint           not null, primary key
#  account_deleted_at        :datetime
#  age_consistent            :boolean
#  call_scheduled_for        :datetime
#  decided_at                :datetime
#  decision_reason           :text
#  document_purged_at        :datetime
#  document_type             :string
#  escalated_at              :datetime
#  escalation_note           :text
#  escalation_resolution     :string
#  escalation_resolved_at    :datetime
#  guardian_attended         :boolean          default(FALSE), not null
#  knot_review_reason        :string
#  pre_review_started_at     :datetime
#  pre_reviewed_at           :datetime
#  region_consistent         :boolean
#  resubmission_note         :text
#  reverification_reason     :string
#  reverification_required_at :datetime
#  status                    :string           default("submitted"), not null
#  verification_method       :string           default("document_call"), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  call_scheduled_by_id      :bigint
#  escalation_resolved_by_id :bigint
#  guardian_consent_id       :bigint
#  knot_id                   :bigint
#  pre_reviewer_id           :bigint
#  previous_attempt_id       :bigint
#  second_verifier_id        :bigint
#  user_id                   :bigint
#  verifier_id               :bigint
#
# Indexes
#
#  index_verifications_on_account_deleted_at         (account_deleted_at)
#  index_verifications_on_call_scheduled_by_id       (call_scheduled_by_id)
#  index_verifications_on_escalation_resolved_by_id  (escalation_resolved_by_id)
#  index_verifications_on_guardian_consent_id        (guardian_consent_id)
#  index_verifications_on_knot_id                    (knot_id)
#  index_verifications_on_pre_reviewer_id            (pre_reviewer_id)
#  index_verifications_on_previous_attempt_id        (previous_attempt_id)
#  index_verifications_on_second_verifier_id         (second_verifier_id)
#  index_verifications_on_status                     (status)
#  index_verifications_on_user_id                    (user_id)
#  index_verifications_on_verifier_id                (verifier_id)
#
# Foreign Keys
#
#  fk_rails_...  (call_scheduled_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (escalation_resolved_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (guardian_consent_id => guardian_consents.id) ON DELETE => nullify
#  fk_rails_...  (knot_id => knots.id) ON DELETE => nullify
#  fk_rails_...  (pre_reviewer_id => users.id) ON DELETE => nullify
#  fk_rails_...  (previous_attempt_id => verifications.id) ON DELETE => nullify
#  fk_rails_...  (second_verifier_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#  fk_rails_...  (verifier_id => users.id) ON DELETE => nullify
#
FactoryBot.define do
  factory :verification do
    user factory: %i[user verified]
    verification_method { "document_call" }
    document_type { "passport" }
    id_document { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/id_document.png"), "image/png") }

    trait :pre_review do
      status { "pre_review" }
      pre_reviewer factory: %i[user identity_team]
      pre_review_started_at { 1.hour.ago }
    end

    trait :awaiting_call do
      status { "awaiting_call" }
      pre_reviewer factory: %i[user identity_team]
      pre_review_started_at { 2.days.ago }
      pre_reviewed_at { 1.day.ago }
    end

    trait :call_scheduled do
      status { "call_scheduled" }
      pre_reviewer factory: %i[user identity_team]
      pre_review_started_at { 2.days.ago }
      pre_reviewed_at { 1.day.ago }
      call_scheduled_for { 1.hour.from_now }
    end

    trait :verified do
      status { "verified" }
      verifier factory: %i[user identity_team]
      age_consistent { true }
      region_consistent { true }
      decision_reason { "Face matched the ID on the call." }
      decided_at { 1.day.ago }
    end

    trait :failed do
      status { "failed" }
      verifier factory: %i[user identity_team]
      age_consistent { true }
      region_consistent { true }
      decision_reason { "The ID on the call was not the uploaded ID." }
      decided_at { 1.day.ago }
    end
  end

  factory :break_glass_record do
    verification
    user { verification.user }
    requested_by factory: %i[user identity_team]
    reason { "Fraud report: check the stored document." }
  end
end
