# frozen_string_literal: true

# == Schema Information
#
# Table name: guardian_consents
# Database name: primary
#
#  id                        :bigint           not null, primary key
#  account_deleted_at        :datetime
#  expires_at                :datetime
#  flags                     :jsonb            not null
#  granted_at                :datetime
#  granted_fingerprint       :string
#  granted_ip                :string
#  granted_user_agent        :string
#  guardian_email_ciphertext :text
#  guardian_name_ciphertext  :text
#  note                      :text
#  review_note               :text
#  reviewed_at               :datetime
#  revoked_at                :datetime
#  sent_at                   :datetime
#  signed_name_ciphertext    :text
#  status                    :string           default("pending"), not null
#  text_version              :string
#  token_digest              :string
#  verification_note         :text
#  verified_at               :datetime
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  recorded_by_id            :bigint
#  reviewed_by_id            :bigint
#  revoked_by_id             :bigint
#  user_id                   :bigint
#  verified_by_id            :bigint
#
# Indexes
#
#  index_guardian_consents_on_recorded_by_id  (recorded_by_id)
#  index_guardian_consents_on_reviewed_by_id  (reviewed_by_id)
#  index_guardian_consents_on_revoked_by_id   (revoked_by_id)
#  index_guardian_consents_on_token_digest    (token_digest) UNIQUE
#  index_guardian_consents_on_user_id         (user_id)
#  index_guardian_consents_on_verified_by_id  (verified_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (recorded_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (reviewed_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (revoked_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#  fk_rails_...  (verified_by_id => users.id) ON DELETE => nullify
#
FactoryBot.define do
  factory :guardian_consent do
    user factory: %i[user verified minor]
    guardian_name { "Grace Hopper" }
    sequence(:guardian_email) { |n| "guardian#{n}@example.org" }
    # Mirrors GuardianConsent.issue!, but keeps the raw token reachable from
    # the spec.
    transient do
      raw_token { SecureRandom.urlsafe_base64(32) }
    end

    token_digest { GuardianConsent.digest_for(raw_token) }
    sent_at { Time.current }
    expires_at { GuardianConsent::LINK_LIFETIME.from_now }

    trait :granted do
      status { "granted" }
      signed_name { "Grace Hopper" }
      granted_at { 1.day.ago }
      text_version { GuardianConsent::TEXT_VERSION }
    end
  end
end
