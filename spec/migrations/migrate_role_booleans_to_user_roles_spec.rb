# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261020130100_migrate_role_booleans_to_user_roles")

# The data migration: each true role boolean becomes a user_roles row, and the
# production patch lead p_ids become patch_lead roles scoped to ganymede.
RSpec.describe MigrateRoleBooleansToUserRoles do
  def connection = ActiveRecord::Base.connection

  # The old columns are ignored by User, so set them with SQL.
  def set_columns(user, **columns)
    assignments = columns.map { |column, value| "#{column} = #{value}" }.join(", ")
    connection.execute("UPDATE users SET #{assignments} WHERE id = #{user.id}")
  end

  def migrate = ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:up) }

  def rows = UserRole.active.includes(:role).map { |row| [row.user_id, row.role.key, row.scope, row.reason, row.granted_by_id] }

  it "copies each true boolean into a role row with no grantor and the column in the reason" do
    verifier = create(:user, :verified)
    set_columns(verifier, identity_team: true, identity_key_holder: true, identity_lead: true)
    staff = create(:user, :verified)
    set_columns(staff, is_board: true, is_staff: true, is_contractor: true)
    plain = create(:user, :verified)

    migrate

    expect(rows).to contain_exactly(
      [verifier.id, "verifier", nil, "migrated from identity_team", nil],
      [verifier.id, "identity_lead", nil, "migrated from identity_lead", nil],
      [verifier.id, "key_holder", nil, "migrated from identity_key_holder", nil],
      [staff.id, "board", nil, "migrated from is_board", nil],
      [staff.id, "staff", nil, "migrated from is_staff", nil],
      [staff.id, "contractor", nil, "migrated from is_contractor", nil]
    )
    expect(plain.reload.role_keys).to be_empty
    expect(verifier.reload).to have_attributes(identity_team: true, identity_key_holder: true, identity_lead: true)
    expect(staff.reload).to have_attributes(is_board: true, is_staff: true, is_contractor: true)
  end

  it "moves the patch lead p_ids into patch_lead roles scoped to ganymede, where the user exists" do
    adam = create(:user, :verified, p_id: "PWL8724F96B89")

    migrate

    expect(rows).to contain_exactly([adam.id, "patch_lead", "ganymede", "migrated from knot.yml patch_lead_p_ids", nil])
    expect(KnotGrants.patch_lead?(adam.reload, "ganymede")).to be(true)
  end

  it "does nothing for a patch lead p_id with no user" do
    migrate

    expect(UserRole.count).to eq(0)
  end

  it "fills the roles table and is idempotent" do
    user = create(:user, :verified)
    set_columns(user, is_board: true)

    migrate
    migrate

    expect(Role.pluck(:key)).to include(*RoleRegistry.keys)
    expect(UserRole.where(user:).count).to eq(1)
  end

  it "names the migration as the actor in the permanent log" do
    user = create(:user, :verified)
    set_columns(user, is_staff: true)

    migrate

    expect(PrivilegedAttributeChange.where(user_id: user.id).sole)
      .to have_attributes(operation: "grant", role_key: "staff", actor_label: "migration MigrateRoleBooleansToUserRoles")
  end
end
