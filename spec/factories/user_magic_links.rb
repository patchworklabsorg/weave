# frozen_string_literal: true

# == Schema Information
#
# Table name: user_magic_links
# Database name: primary
#
#  id           :bigint           not null, primary key
#  expires_at   :datetime         not null
#  requested_ip :string
#  token_digest :string           not null
#  used_at      :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_user_magic_links_on_expires_at    (expires_at)
#  index_user_magic_links_on_token_digest  (token_digest) UNIQUE
#  index_user_magic_links_on_user_id       (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :user_magic_link, class: "User::MagicLink" do
    user
    # Mirrors User::MagicLink.issue!, but keeps the raw token reachable from the
    # spec via the transient attribute.
    transient do
      token { SecureRandom.urlsafe_base64(32) }
    end

    token_digest { User::MagicLink.digest_for(token) }
    expires_at { User::MagicLink::EXPIRATION.from_now }
    used_at { nil }

    after(:build) { |link, evaluator| link.token = evaluator.token }

    trait :used do
      used_at { 1.minute.ago }
    end

    trait :expired do
      expires_at { 1.minute.ago }
    end
  end
end
