# frozen_string_literal: true

# A WebAuthn challenge for one user, one purpose and one subject (see
# KeyCustody::Assertions). The raw challenge starts with the purpose and the
# subject, for example "weave:break_glass:brgl_...:" and random bytes, so an
# assertion is bound to one break-glass request. Each challenge works once:
# a replayed assertion finds its challenge consumed.
# == Schema Information
#
# Table name: key_custody_challenges
# Database name: primary
#
#  id          :bigint           not null, primary key
#  challenge   :string           not null
#  consumed_at :datetime
#  expires_at  :datetime         not null
#  purpose     :string           not null
#  subject     :string           not null
#  created_at  :datetime         not null
#  user_id     :bigint           not null
#
# Indexes
#
#  index_key_custody_challenges_on_challenge  (challenge) UNIQUE
#  index_key_custody_challenges_on_user_id    (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
class KeyCustodyChallenge < ApplicationRecord
  PURPOSES = %w[enroll seal_key break_glass ceremony activate rewrap].freeze

  belongs_to :user

  validates :purpose, inclusion: { in: PURPOSES }
  validates :subject, :challenge, :expires_at, presence: true

  scope :usable, -> { where(consumed_at: nil).where("expires_at > ?", Time.current) }

  # Marks the challenge used. Only one caller wins, so a replay fails.
  def consume!
    self.class.where(id:, consumed_at: nil).update_all(consumed_at: Time.current) == 1 # rubocop:disable Rails/SkipsModelValidations
  end

end
