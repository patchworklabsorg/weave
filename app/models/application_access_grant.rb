# frozen_string_literal: true

# Gives a user, or every member of a group, access to one OAuth app whose
# access_policy is "restricted". Grants only allow: there are no deny rules,
# so the answer to "why can't this person get in" is always "no grant matches".
# See AppAccess for how grants are read.
# == Schema Information
#
# Table name: application_access_grants
# Database name: primary
#
#  id             :bigint           not null, primary key
#  grantee_type   :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  application_id :bigint           not null
#  created_by_id  :bigint
#  grantee_id     :bigint           not null
#
# Indexes
#
#  index_application_access_grants_on_created_by_id  (created_by_id)
#  index_application_access_grants_on_grantee        (grantee_type,grantee_id)
#  index_application_access_grants_uniqueness        (application_id,grantee_type,grantee_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (application_id => oauth_applications.id) ON DELETE => cascade
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#
class ApplicationAccessGrant < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :aag

  has_paper_trail

  GRANTEE_TYPES = %w[User Group].freeze

  belongs_to :application, class_name: "Doorkeeper::Application"
  belongs_to :grantee, polymorphic: true
  belongs_to :created_by, class_name: "User", optional: true

  validates :grantee_type, inclusion: { in: GRANTEE_TYPES }
  validates :grantee_id, uniqueness: { scope: [:application_id, :grantee_type], message: "already has access" }

  scope :for_application, ->(application) { where(application_id: application.id) }

  # Removing a grant can end access for the user, or for every group member.
  after_destroy_commit -> { RevokeLostAppAccessJob.perform_later(application_id: application_id) }

end
