# frozen_string_literal: true

# Gives a user, or every active member of a group, one role of one patch (see
# PatchRole). Only a superadmin makes or removes one.
# == Schema Information
#
# Table name: patch_role_assignments
# Database name: primary
#
#  id            :bigint           not null, primary key
#  assignee_type :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  assignee_id   :bigint           not null
#  created_by_id :bigint
#  role_id       :bigint           not null
#
# Indexes
#
#  index_patch_role_assignments_on_assignee       (assignee_type,assignee_id)
#  index_patch_role_assignments_on_created_by_id  (created_by_id)
#  index_patch_role_assignments_uniqueness        (role_id,assignee_type,assignee_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (role_id => patch_roles.id) ON DELETE => cascade
#
class PatchRoleAssignment < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :pras

  has_paper_trail

  ASSIGNEE_TYPES = %w[User Group].freeze

  belongs_to :role, class_name: "PatchRole", inverse_of: :assignments
  belongs_to :assignee, polymorphic: true
  belongs_to :created_by, class_name: "User", optional: true

  validates :assignee_type, inclusion: { in: ASSIGNEE_TYPES }
  validates :assignee_id, uniqueness: { scope: [:role_id, :assignee_type], message: "already has this role" }

end
