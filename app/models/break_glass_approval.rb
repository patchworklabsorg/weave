# frozen_string_literal: true

# One key holder's approval of a BreakGlassRecord: the holder gave their
# share with a hardware key (see BreakGlass.approve and KeyCustody). The
# share itself waits in server memory only. When it leaves memory before the
# request is granted (a restart, or pending_share_minutes passed), the row
# gets lapsed_at and the holder submits again. Nothing else changes a row.
# == Schema Information
#
# Table name: break_glass_approvals
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  lapsed_at             :datetime
#  created_at            :datetime         not null
#  approver_id           :bigint
#  break_glass_record_id :bigint           not null
#  hardware_key_id       :bigint
#
# Indexes
#
#  index_break_glass_approvals_on_approver_id            (approver_id)
#  index_break_glass_approvals_on_break_glass_record_id  (break_glass_record_id)
#  index_break_glass_approvals_on_hardware_key_id        (hardware_key_id)
#  index_break_glass_approvals_on_record_and_approver    (break_glass_record_id,approver_id) UNIQUE WHERE (lapsed_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (approver_id => users.id) ON DELETE => nullify
#  fk_rails_...  (break_glass_record_id => break_glass_records.id)
#  fk_rails_...  (hardware_key_id => identity_hardware_keys.id) ON DELETE => nullify
#
class BreakGlassApproval < ApplicationRecord
  belongs_to :break_glass_record
  belongs_to :approver, class_name: "User", optional: true
  belongs_to :hardware_key, class_name: "IdentityHardwareKey", optional: true

  validates :approver_id, uniqueness: { scope: :break_glass_record_id, conditions: -> { where(lapsed_at: nil) } }, on: :create

  scope :live, -> { where(lapsed_at: nil) }

  def lapsed? = lapsed_at.present?

  def self.lapse!(ids)
    where(id: ids, lapsed_at: nil).update_all(lapsed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def readonly? = persisted? || super

end
