# frozen_string_literal: true

# One step of the notice ladder for a break-glass decryption (see BreakGlass):
#
# - key_holder: the other key holder who approved. Due at once.
# - lead: each identity team lead. Due at once.
# - member: the member whose ID it is. Due after a configured window. An
#   identity team member can delay it for an active fraud investigation, with
#   a reason. The delay holds the notice only after an owner or an identity
#   team lead signs it off (never the requester of the delay or of the
#   access), and for at most max_fraud_delay_days after the notice
#   was first due. Then the notice goes out. The lead hears about the delay,
#   and the board report shows it.
#
# DeliverBreakGlassNoticesJob sends each notice when it is due.
# == Schema Information
#
# Table name: break_glass_notices
# Database name: primary
#
#  id                        :bigint           not null, primary key
#  delay_lifted_at           :datetime
#  delay_reason              :text
#  delay_signed_off_at       :datetime
#  delayed_at                :datetime
#  due_at                    :datetime         not null
#  recipient_kind            :string           not null
#  sent_at                   :datetime
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  break_glass_decryption_id :bigint           not null
#  delay_lifted_by_id        :bigint
#  delay_signed_off_by_id    :bigint
#  delayed_by_id             :bigint
#  recipient_id              :bigint
#
# Indexes
#
#  index_break_glass_notices_on_break_glass_decryption_id  (break_glass_decryption_id)
#  index_break_glass_notices_on_delay_lifted_by_id         (delay_lifted_by_id)
#  index_break_glass_notices_on_delay_signed_off_by_id     (delay_signed_off_by_id)
#  index_break_glass_notices_on_delayed_by_id              (delayed_by_id)
#  index_break_glass_notices_on_recipient_id               (recipient_id)
#  index_break_glass_notices_on_sent_at_and_due_at         (sent_at,due_at)
#
# Foreign Keys
#
#  fk_rails_...  (break_glass_decryption_id => break_glass_decryptions.id)
#  fk_rails_...  (delay_lifted_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (delay_signed_off_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (delayed_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (recipient_id => users.id) ON DELETE => nullify
#
class BreakGlassNotice < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :bgn

  KINDS = %w[key_holder lead member].freeze

  has_paper_trail

  belongs_to :break_glass_decryption
  belongs_to :recipient, class_name: "User", optional: true
  belongs_to :delayed_by, class_name: "User", optional: true
  belongs_to :delay_lifted_by, class_name: "User", optional: true
  belongs_to :delay_signed_off_by, class_name: "User", optional: true

  validates :recipient_kind, inclusion: { in: KINDS }
  validates :delay_reason, presence: true, if: :delayed_at?

  scope :unsent, -> { where(sent_at: nil) }
  # A delay was asked for and is not lifted (signed off or not).
  scope :delayed, -> { unsent.where.not(delayed_at: nil).where(delay_lifted_at: nil) }
  # Due now: past due_at, and not held by a signed-off delay that is still
  # inside its maximum.
  scope :due, lambda {
    now = Time.current
    unsent.where(due_at: ..now)
          .where("delay_signed_off_at IS NULL OR delay_lifted_at IS NOT NULL OR due_at <= ?",
                 now - VerificationSettings.max_fraud_delay)
  }

  def member? = recipient_kind == "member"

  # A delay was asked for and is not lifted.
  def delayed? = delayed_at.present? && delay_lifted_at.nil?

  def delay_signed_off? = delayed? && delay_signed_off_at.present?

  # The latest time a delay can hold the notice.
  def delay_ends_at = due_at + VerificationSettings.max_fraud_delay

  # The notice waits because of a signed-off delay that has not run out.
  def held? = delay_signed_off? && Time.current < delay_ends_at

  def sent? = sent_at.present?

  delegate :break_glass_record, to: :break_glass_decryption

end
