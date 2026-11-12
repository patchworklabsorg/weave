# frozen_string_literal: true

# A role that a superadmin defines for one patch, such as "viewer". Users get
# it directly or through a group (PatchRoleAssignment). Apps read the keys in
# the `patches` claim (see PatchRoles), so a role can open a patch's data in
# an app such as Quilt.
#
# The key is the stable name that apps see, so it never changes after the
# role is created. Renaming a role changes only its display name. The key
# "lead" is reserved: the claim sends it for the patch_lead role, which
# identity governance grants (config/roles.yml).
# == Schema Information
#
# Table name: patch_roles
# Database name: primary
#
#  id            :bigint           not null, primary key
#  description   :text
#  key           :string           not null
#  name          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  created_by_id :bigint
#  patch_id      :bigint           not null
#
# Indexes
#
#  index_patch_roles_on_created_by_id     (created_by_id)
#  index_patch_roles_on_patch_id_and_key  (patch_id,key) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (patch_id => patches.id) ON DELETE => cascade
#
class PatchRole < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :prole

  has_paper_trail

  KEY_FORMAT = ApplicationRole::KEY_FORMAT
  # Keys that PatchRoles sends for a governance role (see PatchRoles::LEAD).
  RESERVED_KEYS = %w[lead].freeze

  belongs_to :patch
  belongs_to :created_by, class_name: "User", optional: true
  has_many :assignments, class_name: "PatchRoleAssignment", foreign_key: :role_id,
                         inverse_of: :role, dependent: :destroy

  validates :name, presence: true, length: { maximum: 100 }
  validates :description, length: { maximum: 2000 }
  validates :key, presence: true, length: { maximum: 64 }, format: { with: KEY_FORMAT },
                  exclusion: { in: RESERVED_KEYS, message: "is reserved for the patch lead" },
                  uniqueness: { scope: :patch_id }
  validate :key_unchanged, on: :update

  # Roles held by a user, directly or through an unexpired group membership
  # (the same rule as ApplicationRole.held_by).
  scope :held_by, lambda { |user|
    direct = PatchRoleAssignment.where(assignee: user)
    via_group = PatchRoleAssignment.where(assignee_type: "Group", assignee_id: user.active_group_memberships.select(:group_id))
    where(id: direct.or(via_group).select(:role_id))
  }

  private

  def key_unchanged
    errors.add(:key, "can't be changed after the role is created") if key_changed?
  end

end
