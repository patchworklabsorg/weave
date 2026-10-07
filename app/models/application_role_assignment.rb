# frozen_string_literal: true

# Gives a user, or every member of a group, one role in one OAuth app.
# A role assignment also gives access to the app when it is restricted
# (see AppAccess).
# == Schema Information
#
# Table name: application_role_assignments
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
#  index_application_role_assignments_on_assignee       (assignee_type,assignee_id)
#  index_application_role_assignments_on_created_by_id  (created_by_id)
#  index_application_role_assignments_uniqueness        (role_id,assignee_type,assignee_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (role_id => application_roles.id) ON DELETE => cascade
#
class ApplicationRoleAssignment < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :aras

  has_paper_trail

  ASSIGNEE_TYPES = %w[User Group].freeze

  belongs_to :role, class_name: "ApplicationRole", inverse_of: :assignments
  belongs_to :assignee, polymorphic: true
  belongs_to :created_by, class_name: "User", optional: true

  validates :assignee_type, inclusion: { in: ASSIGNEE_TYPES }
  validates :assignee_id, uniqueness: { scope: [:role_id, :assignee_type], message: "already has this role" }

  scope :for_application, ->(application) { joins(:role).where(application_roles: { application_id: application.id }) }

  # Losing a role can end access to a restricted app.
  after_destroy_commit -> { RevokeLostAppAccessJob.perform_later(application_id: role.application_id) }

end
