# frozen_string_literal: true

# Roles that a superadmin defines for one patch, such as "viewer" or
# "reviewer", and who holds them: a user, or every active member of a group
# (see PatchRole, PatchRoleAssignment and PatchRoles). The same design as
# application_roles and application_role_assignments.
class CreatePatchRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :patch_roles do |t|
      t.references :patch, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }

      t.timestamps
    end

    add_index :patch_roles, [:patch_id, :key], unique: true

    create_table :patch_role_assignments do |t|
      t.references :role, null: false, index: false, foreign_key: { to_table: :patch_roles, on_delete: :cascade }
      t.references :assignee, null: false, polymorphic: true
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }

      t.timestamps
    end

    add_index :patch_role_assignments, [:role_id, :assignee_type, :assignee_id], unique: true,
                                                                                 name: "index_patch_role_assignments_uniqueness"
  end

end
