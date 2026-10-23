# frozen_string_literal: true

# A member's consent to be counted in one funder's report (see
# FunderProfiles and FunderReport). Only a funder with requires_member_consent
# uses it. The member gives or withdraws it on the demographics page. A
# withdrawal keeps the row with withdrawn_at, so the history shows when the
# member was counted. A new consent is a new row.
#
# The rows are account data: the deletion pipeline deletes them with the
# user, and takeout exports them.
# == Schema Information
#
# Table name: funder_consents
# Database name: primary
#
#  id           :bigint           not null, primary key
#  funder       :string           not null
#  given_at     :datetime         not null
#  withdrawn_at :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_funder_consents_on_funder                (funder)
#  index_funder_consents_on_user_and_funder_live  (user_id,funder) UNIQUE WHERE (withdrawn_at IS NULL)
#  index_funder_consents_on_user_id               (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
class FunderConsent < ApplicationRecord
  belongs_to :user

  validates :funder, inclusion: { in: ->(_) { FunderProfiles.all.select(&:consent_required?).map(&:key) } }
  validates :given_at, presence: true

  scope :live, -> { where(withdrawn_at: nil) }

  def live? = withdrawn_at.nil?

  def profile = FunderProfiles.find(funder)

  class << self
    # The member gives consent. Returns the live row.
    def give!(user, funder)
      transaction do
        User.lock.find(user.id) # Not User#lock!: that locks the account.
        live.find_by(user:, funder: funder.to_s) || create!(user:, funder: funder.to_s, given_at: Time.current)
      end
    end

    # The member withdraws consent. Reports made after this do not count
    # them for that funder.
    def withdraw!(user, funder) = live.where(user:, funder: funder.to_s).update_all(withdrawn_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

    # The members who consent now to this funder.
    def user_ids_for(funder) = live.where(funder: funder.to_s).select(:user_id)

  end

end
