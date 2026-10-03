# frozen_string_literal: true

# One user's place in one group.
#
# A membership with an `expires_at` in the past grants nothing: every access
# check goes through the `active` scope. ExpireGroupMembershipsJob then removes
# the row, and PaperTrail keeps the record of who lost access and when.
#
# `source` says who manages the row. `system` rows belong to the attribute sync
# for system groups and are never touched by hand; `manual` rows are added in
# the admin panel.
# == Schema Information
#
# Table name: group_memberships
# Database name: primary
#
#  id          :bigint           not null, primary key
#  expires_at  :datetime
#  source      :string           default("manual"), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  added_by_id :bigint
#  group_id    :bigint           not null
#  user_id     :bigint           not null
#
# Indexes
#
#  index_group_memberships_on_added_by_id           (added_by_id)
#  index_group_memberships_on_expires_at            (expires_at) WHERE (expires_at IS NOT NULL)
#  index_group_memberships_on_group_id_and_user_id  (group_id,user_id) UNIQUE
#  index_group_memberships_on_user_id               (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (added_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (group_id => groups.id)
#  fk_rails_...  (user_id => users.id)
#
class Group::Membership < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :gmem

  self.table_name = "group_memberships"

  has_paper_trail

  enum :source, { manual: "manual", system: "system" }, default: "manual", validate: true

  belongs_to :group
  belongs_to :user
  belongs_to :added_by, class_name: "User", optional: true

  scope :active, -> { where(expires_at: nil).or(where(expires_at: Time.current..)) }
  scope :expired, -> { where(expires_at: ...Time.current) }

  validates :user_id, uniqueness: { scope: :group_id, message: "is already in this group" }
  validate :expires_in_the_future, if: -> { expires_at.present? && will_save_change_to_expires_at? }

  def expired? = expires_at.present? && expires_at <= Time.current

  def active? = !expired?

  private

  def expires_in_the_future
    errors.add(:expires_at, "must be in the future") if expires_at <= Time.current
  end

end
