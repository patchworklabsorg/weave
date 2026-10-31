# frozen_string_literal: true

# == Schema Information
#
# Table name: users
# Database name: primary
#
#  id                       :bigint           not null, primary key
#  acknowledged_over_13_at  :datetime
#  birthday                 :date
#  code_of_conduct_exempt   :boolean          default(FALSE), not null
#  confirmation_sent_at     :datetime
#  confirmation_token       :string
#  directory_linked_at      :datetime
#  email                    :string           not null
#  email_confirmed_at       :datetime
#  first_name               :string           not null
#  last_name                :string           not null
#  legal_first_name         :string
#  legal_last_name          :string
#  locked_at                :datetime
#  password_digest          :string           not null
#  phone_number             :string
#  pronouns                 :string
#  referral_source          :string
#  referral_source_detail   :string
#  role                     :integer          default("user"), not null
#  session_duration_seconds :integer          default(2592000), not null
#  slack_birthday           :date
#  slack_city               :string
#  slack_coc_accepted_at    :datetime
#  slack_coc_messages       :jsonb            not null
#  slack_coc_requested_at   :datetime
#  slack_cost_center        :string
#  slack_country            :string
#  slack_department         :string
#  slack_display_name       :string
#  slack_division           :string
#  slack_github             :string
#  slack_invited_at         :datetime
#  slack_joined_at          :datetime
#  slack_linkedin           :string
#  slack_membership         :string           default("pending"), not null
#  slack_organization       :string
#  slack_phone              :string
#  slack_profile_image_url  :string
#  slack_profile_synced_at  :datetime
#  slack_pronouns           :string
#  slack_role_description   :text
#  slack_start_date         :date
#  slack_state              :string
#  slack_status_emoji       :string
#  slack_status_text        :string
#  slack_title              :string
#  slack_website            :string
#  status                   :enum             default("active"), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  manager_id               :bigint
#  p_id                     :string           not null
#  slack_id                 :string
#  slack_manager_id         :string
#  webauthn_id              :string
#
# Indexes
#
#  index_users_on_confirmation_token  (confirmation_token) UNIQUE
#  index_users_on_email               (email) UNIQUE
#  index_users_on_manager_id          (manager_id)
#  index_users_on_p_id                (p_id) UNIQUE
#  index_users_on_webauthn_id         (webauthn_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (manager_id => users.id)
#
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    first_name { "John" }
    last_name { "Doe" }
    password { "SecurePassword123!" }
    password_confirmation { "SecurePassword123!" }
    role { :user }
    status { "active" }
    # An adult. Weave asks for a birthday before anything else when it is
    # missing (see User#slack_onboarding_step).
    birthday { 30.years.ago.to_date }

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

    # Every OAuth app requires the code of conduct unless it is opted out (see
    # AppAccess).
    trait :accepted_code_of_conduct do
      slack_coc_accepted_at { 1.day.ago }
    end

    # Under 18, so they need a parent or guardian's consent (see
    # GuardianConsent).
    trait :minor do
      birthday { 15.years.ago.to_date }
    end

    # The role traits create user_roles rows (see RoleGrants): the
    # compatibility setters (identity_team, is_board, ...) stage the role,
    # and the save grants it.
    #
    # Runs identity verification (see Verification). The verification pages
    # (/identity) do not need the admin role. The trait gives it anyway,
    # because the deletion review and the Knot pages are in /admin.
    trait :identity_team do
      role { :admin }
      email_confirmed_at { Time.current }
      identity_team { true }
    end

    trait :key_holder do
      identity_team
      identity_key_holder { true }
    end

    trait :identity_lead do
      identity_team
      identity_lead { true }
    end

    trait :board do
      is_board { true }
    end

    trait :staff do
      is_staff { true }
    end

    trait :contractor do
      is_contractor { true }
    end

    # The patch lead of a program (default ganymede): a scoped role.
    trait :patch_lead do
      transient do
        patch_lead_program { "ganymede" }
      end

      after(:create) do |user, evaluator|
        RoleGrants.grant!(user, "patch_lead", scope: evaluator.patch_lead_program, reason: "factory")
      end
    end

    trait :with_magic_link do
      transient do
        magic_link_token { SecureRandom.urlsafe_base64(32) }
      end

      after(:create) do |user, evaluator|
        create(:user_magic_link, user: user, token: evaluator.magic_link_token)
      end
    end
  end
end
