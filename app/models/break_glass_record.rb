# frozen_string_literal: true

# A request to decrypt a stored ID image outside pre-review (see BreakGlass).
#
# An identity team member asks, with a written reason. Two different key
# holders must approve. Then only the requester can decrypt the image, for a
# configured number of minutes. Each decryption is a BreakGlassDecryption,
# and each decryption sends the notice ladder (BreakGlassNotice).
# == Schema Information
#
# Table name: break_glass_records
# Database name: primary
#
#  id              :bigint           not null, primary key
#  denial_reason   :text
#  denied_at       :datetime
#  expires_at      :datetime
#  granted_at      :datetime
#  reason          :text             not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  denied_by_id    :bigint
#  requested_by_id :bigint
#  user_id         :bigint
#  verification_id :bigint           not null
#
# Indexes
#
#  index_break_glass_records_on_denied_by_id     (denied_by_id)
#  index_break_glass_records_on_requested_by_id  (requested_by_id)
#  index_break_glass_records_on_user_id          (user_id)
#  index_break_glass_records_on_verification_id  (verification_id)
#
# Foreign Keys
#
#  fk_rails_...  (denied_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (requested_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#  fk_rails_...  (verification_id => verifications.id)
#
class BreakGlassRecord < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :brgl

  has_paper_trail

  belongs_to :verification
  belongs_to :user, optional: true
  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :denied_by, class_name: "User", optional: true
  has_many :approvals, class_name: "BreakGlassApproval", dependent: :restrict_with_exception
  has_many :approvers, through: :approvals
  has_many :decryptions, class_name: "BreakGlassDecryption", dependent: :restrict_with_exception

  validates :reason, presence: true, length: { minimum: 10, maximum: 2000 }
  validates :denial_reason, presence: true, if: :denied_at?

  scope :pending, -> { where(granted_at: nil, denied_at: nil) }

  def denied? = denied_at.present?

  def granted? = granted_at.present? && !denied?

  def pending? = !granted? && !denied?

  def expired? = granted? && expires_at <= Time.current

  def usable_by?(user) = granted? && !expired? && requested_by_id == user&.id

  def status
    if denied? then :denied
    elsif expired? then :expired
    elsif granted? then :granted
    else
      :pending
    end
  end

end
