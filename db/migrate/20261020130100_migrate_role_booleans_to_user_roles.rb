# frozen_string_literal: true

# Fills the roles table from config/roles.yml, then copies each true role
# boolean on users into a user_roles row (granted_by empty, reason "migrated
# from <column>"). Also moves the patch leads from the old
# patch_lead_p_ids list in config/kyc/knot.yml into patch_lead roles scoped to
# the program, for each user that exists here.
#
# Idempotent: a person who already holds the role gets no second row. The
# permanent log names this migration as the actor.
#
# The boolean columns stay (Weave ignores them, see User::LEGACY_ROLE_COLUMNS).
# Removing them is a later step in docs/KYC_ROLLOUT.md.
class MigrateRoleBooleansToUserRoles < ActiveRecord::Migration[8.1]
  # The role of each old boolean column, as of this migration.
  COLUMNS = {
    "identity_team" => "verifier",
    "identity_lead" => "identity_lead",
    "identity_key_holder" => "key_holder",
    "is_board" => "board",
    "is_staff" => "staff",
    "is_contractor" => "contractor"
  }.freeze

  # The production patch_lead_p_ids of config/kyc/knot.yml before this
  # migration (Adam, the Ganymede patch lead). Other deployments have no such
  # user, so nothing happens there.
  PATCH_LEADS = { "ganymede" => ["PWL8724F96B89"] }.freeze

  def up
    Role.reset_column_information
    RoleRegistry.sync!(model: Role)

    # Plain inserts into the new table: no lock on users.
    safety_assured do
      execute "SELECT set_config('weave.actor_label', 'migration #{self.class.name}', true)"

      COLUMNS.each do |column, role_key|
        execute <<~SQL.squish
          INSERT INTO user_roles (user_id, role_id, scope, granted_at, reason)
          SELECT users.id, roles.id, NULL, now(), #{quote("migrated from #{column}")}
          FROM users JOIN roles ON roles.key = #{quote(role_key)}
          WHERE users.#{column} = true
            AND NOT EXISTS (
              SELECT 1 FROM user_roles existing
              WHERE existing.user_id = users.id AND existing.role_id = roles.id
                AND existing.scope IS NULL AND existing.revoked_at IS NULL
            )
          ORDER BY users.id
        SQL
      end

      PATCH_LEADS.each do |program, p_ids|
        p_ids.each do |p_id|
          execute <<~SQL.squish
            INSERT INTO user_roles (user_id, role_id, scope, granted_at, reason)
            SELECT users.id, roles.id, #{quote(program)}, now(), #{quote('migrated from knot.yml patch_lead_p_ids')}
            FROM users JOIN roles ON roles.key = 'patch_lead'
            WHERE users.p_id = #{quote(p_id)}
              AND NOT EXISTS (
                SELECT 1 FROM user_roles existing
                WHERE existing.user_id = users.id AND existing.role_id = roles.id
                  AND existing.scope = #{quote(program)} AND existing.revoked_at IS NULL
              )
          SQL
        end
      end
    end
  end

  # The rows are permanent (a trigger refuses DELETE), and the boolean
  # columns still hold the old values. Rolling back CreateRoles drops the
  # table.
  def down; end

  private

  def quote(value) = connection.quote(value)

  # A model of this migration's own, so a later change to Role can't break it.
  class Role < ActiveRecord::Base
    self.table_name = "roles"
  end
  private_constant :Role
end
