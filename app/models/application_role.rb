# frozen_string_literal: true

# A role that one OAuth app defines for itself, such as Krater's "reviewer".
# Users get a role directly or through a group (ApplicationRoleAssignment).
# The app reads the keys of the user's roles from the `roles` claim.
#
# The key is the stable name the app sees, so it never changes after the role
# is created. Renaming a role changes only its display name.
# == Schema Information
#
# Table name: application_roles
# Database name: primary
#
#  id             :bigint           not null, primary key
#  description    :text
#  key            :string           not null
#  name           :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  application_id :bigint           not null
#  created_by_id  :bigint
#
# Indexes
#
#  index_application_roles_on_application_id_and_key  (application_id,key) UNIQUE
#  index_application_roles_on_created_by_id           (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (application_id => oauth_applications.id) ON DELETE => cascade
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#
class ApplicationRole < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :arole

  has_paper_trail

  KEY_FORMAT = /\A[a-z0-9]+(?:[-_:][a-z0-9]+)*\z/

  belongs_to :application, class_name: "Doorkeeper::Application"
  belongs_to :created_by, class_name: "User", optional: true
  has_many :assignments, class_name: "ApplicationRoleAssignment", foreign_key: :role_id,
                         inverse_of: :role, dependent: :destroy

  validates :name, presence: true, length: { maximum: 100 }
  validates :key, presence: true, length: { maximum: 64 }, format: { with: KEY_FORMAT },
                  uniqueness: { scope: :application_id }
  validate :key_unchanged, on: :update

  scope :for_application, ->(application) { where(application_id: application.id) }

  # Roles held by a user, directly or through an unexpired group membership.
  scope :held_by, lambda { |user|
    direct = ApplicationRoleAssignment.where(assignee: user)
    via_group = ApplicationRoleAssignment.where(assignee_type: "Group", assignee_id: user.active_group_memberships.select(:group_id))
    where(id: direct.or(via_group).select(:role_id))
  }

  # Deleting a role can end access to a restricted app for its holders.
  after_destroy_commit -> { RevokeLostAppAccessJob.perform_later(application_id: application_id) }

  private

  def key_unchanged
    errors.add(:key, "can't be changed after the role is created") if key_changed?
  end

end
