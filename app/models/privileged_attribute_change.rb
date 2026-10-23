# frozen_string_literal: true

# The permanent log of privileged user attributes (see docs/KYC.md "The
# permanent log"). A Postgres trigger on users writes one row for each change
# to is_board, identity_team, identity_key_holder, identity_lead or role, so a
# console write, update_column or raw SQL is in the log too. Weave never
# writes a row itself.
#
# Rows are permanent. The database refuses UPDATE, DELETE and TRUNCATE on the
# table, and there is no foreign key to users, so the deletion pipeline and the
# retention jobs keep every row. This model is read-only.
#
# actor_id and actor_label come from the weave.actor_id and weave.actor_label
# settings of the database session (see PrivilegedChangeActor). db_user is the
# database role that made the change.
class PrivilegedAttributeChange < ApplicationRecord
  ATTRIBUTES = %w[is_board identity_team identity_key_holder identity_lead role].freeze

  belongs_to :user, optional: true
  belongs_to :actor, class_name: "User", optional: true

  scope :newest_first, -> { order(changed_at: :desc, id: :desc) }
  scope :between, ->(range) { where(changed_at: range) }

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
    "#{user_p_id || "user #{user_id}"}: #{attribute_name} #{before_value || 'unset'} -> #{after_value}"
  end

  private

  # role is stored as its integer. Show the role name too.
  def display(value)
    return value unless attribute_name == "role" && value.present?

    name = User.roles.key(value.to_i)
    name ? "#{name} (#{value})" : value
  end

end
