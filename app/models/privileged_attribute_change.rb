# frozen_string_literal: true

# The permanent log of privileged user attributes (see docs/KYC.md "The
# permanent log"). Postgres triggers write it, so a console write,
# update_column or raw SQL is in the log too. Weave never writes a row itself.
#
# - The trigger on user_roles writes one row for each grant (operation
#   "grant") and each revoke ("revoke") of a role, with role_key, role_scope
#   and user_role_id. attribute_name is "role:<key>" or "role:<key>[<scope>]".
# - The trigger on users writes one row for each change to role (the admin
#   tier).
# - Rows from before the roles table (2026-10-20) also name the old boolean
#   columns is_board, identity_team, identity_key_holder and identity_lead.
#
# Rows are permanent. The database refuses UPDATE, DELETE and TRUNCATE on the
# table, and there is no foreign key to users, so the deletion pipeline and the
# retention jobs keep every row. This model is read-only.
#
# actor_id and actor_label come from the weave.actor_id and weave.actor_label
# settings of the database session (see PrivilegedChangeActor). db_user is the
# database role that made the change.
# == Schema Information
# Schema version: 20261023120000
#
# Table name: privileged_attribute_changes
# Database name: primary
#
#  id             :bigint           not null, primary key
#  actor_label    :string
#  attribute_name :string           not null
#  changed_at     :datetime         not null
#  db_user        :string           not null
#  new_value      :text
#  old_value      :text
#  operation      :string           not null
#  role_key       :string
#  role_scope     :string
#  actor_id       :bigint
#  user_id        :bigint           not null
#  user_p_id      :string
#  user_role_id   :bigint
#
# Indexes
#
#  index_privileged_attribute_changes_on_changed_at  (changed_at)
#  index_privileged_attribute_changes_on_user_id     (user_id)
#
class PrivilegedAttributeChange < ApplicationRecord
  # The user columns the users trigger logs. Older rows also name the old
  # role booleans (LEGACY_ATTRIBUTES).
  ATTRIBUTES = %w[role].freeze
  LEGACY_ATTRIBUTES = %w[is_board identity_team identity_key_holder identity_lead].freeze
  ROLE_OPERATIONS = %w[grant revoke].freeze

  belongs_to :user, optional: true
  belongs_to :actor, class_name: "User", optional: true

  scope :newest_first, -> { order(changed_at: :desc, id: :desc) }
  scope :between, ->(range) { where(changed_at: range) }
  scope :role_changes, -> { where(operation: ROLE_OPERATIONS) }

  def role_change? = ROLE_OPERATIONS.include?(operation)

  def readonly? = true

  def before_value = display(old_value)

  def after_value = display(new_value)

  # Who made the change, as far as the log knows.
  def actor_name
    name = actor&.full_name
    name ||= "user #{actor_id} (deleted)" if actor_id
    [name, actor_label].compact.join(", ").presence || "unknown (database role #{db_user})"
  end

  def summary
    who = user_p_id || "user #{user_id}"
    return "#{who}: #{operation} role #{role_key}#{" (#{role_scope})" if role_scope}" if role_change?

    "#{who}: #{attribute_name} #{before_value || 'unset'} -> #{after_value}"
  end

  private

  # role is stored as its integer. Show the role name too.
  def display(value)
    return value unless attribute_name == "role" && value.present?

    name = User.roles.key(value.to_i)
    name ? "#{name} (#{value})" : value
  end

end
