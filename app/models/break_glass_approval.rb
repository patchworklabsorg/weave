# frozen_string_literal: true

# One key holder's approval of a BreakGlassRecord. A row never changes.
# == Schema Information
#
# Table name: break_glass_approvals
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  created_at            :datetime         not null
#  approver_id           :bigint
#  break_glass_record_id :bigint           not null
#
# Indexes
#
#  index_break_glass_approvals_on_record_and_approver    (break_glass_record_id,approver_id) UNIQUE
#  index_break_glass_approvals_on_approver_id            (approver_id)
#  index_break_glass_approvals_on_break_glass_record_id  (break_glass_record_id)
#
# Foreign Keys
#
#  fk_rails_...  (approver_id => users.id) ON DELETE => nullify
#  fk_rails_...  (break_glass_record_id => break_glass_records.id)
#
class BreakGlassApproval < ApplicationRecord
  belongs_to :break_glass_record
  belongs_to :approver, class_name: "User", optional: true

  validates :approver_id, uniqueness: { scope: :break_glass_record_id }, on: :create

  def readonly? = persisted? || super

end
