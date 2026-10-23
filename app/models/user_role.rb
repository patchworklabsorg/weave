# frozen_string_literal: true

# == Schema Information
#
# Table name: user_roles
# Database name: primary
#
#  id                              :bigint           not null, primary key
#  granted_at                      :datetime         not null
#  reason                          :text
#  revoke_reason                   :text
#  revoked_at                      :datetime
#  scope                           :string
#  created_at                      :datetime         not null
#  granted_by_id                   :bigint
#  identity_governance_proposal_id :bigint
#  revoked_by_id                   :bigint
#  role_id                         :bigint           not null
#  user_id                         :bigint
#
# Indexes
#
#  index_user_roles_active_by_role                      (role_id,scope) WHERE (revoked_at IS NULL)
#  index_user_roles_on_granted_by_id                    (granted_by_id)
#  index_user_roles_on_identity_governance_proposal_id  (identity_governance_proposal_id)
#  index_user_roles_on_revoked_by_id                    (revoked_by_id)
#  index_user_roles_on_role_id                          (role_id)
#  index_user_roles_on_user_id                          (user_id)
#  index_user_roles_one_active_assignment               (user_id, role_id, COALESCE(scope, ''::character varying)) UNIQUE WHERE (revoked_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (granted_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (identity_governance_proposal_id => identity_governance_proposals.id) ON DELETE => nullify
#  fk_rails_...  (revoked_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (role_id => roles.id)
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
# One assignment of a Role to a user, global (scope nil) or for one scope
# such as a program key (see RoleGrants and docs/KYC.md "Roles").
#
# Rows are permanent. A revoke sets revoked_at, revoked_by and revoke_reason
# once. The database refuses every other UPDATE, and DELETE and TRUNCATE. A
# trigger writes each grant and revoke to the permanent log
# (PrivilegedAttributeChange). Write through RoleGrants, not this model.
class UserRole < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :urol

  belongs_to :user, optional: true
  belongs_to :role
  belongs_to :granted_by, class_name: "User", optional: true
  belongs_to :revoked_by, class_name: "User", optional: true
  belongs_to :identity_governance_proposal, optional: true

  scope :active, -> { where(revoked_at: nil) }
  scope :revoked, -> { where.not(revoked_at: nil) }
  scope :for_role, ->(key) { joins(:role).where(roles: { key: key.to_s }) }

  validates :granted_at, presence: true
  validate :scope_fits_role, on: :create

  before_destroy { raise ActiveRecord::ReadOnlyRecord, "User roles are permanent. Revoke the role instead." }

  def active? = revoked_at.nil?

  def revoked? = !active?

  def key = role.key

  def proposal = identity_governance_proposal

  # "Patch lead (ganymede)" or "Staff".
  def label = scope ? "#{role.name} (#{scope})" : role.name

  private

  def scope_fits_role
    return if role.nil? || !RoleRegistry.known?(role.key)
    return if RoleRegistry.valid_scope?(role.key, scope)

    errors.add(:scope, role.scopable ? "must be one of: #{RoleRegistry.scopes_for(role.key).join(', ')}" : "must be empty for a global role")
  end

end
