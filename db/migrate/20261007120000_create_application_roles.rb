# frozen_string_literal: true

class CreateApplicationRoles < ActiveRecord::Migration[8.1]
  def change
    create_table :application_roles do |t|
      t.references :application, null: false, index: false,
                                 foreign_key: { to_table: :oauth_applications, on_delete: :cascade }
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }

      t.timestamps
    end

    add_index :application_roles, [:application_id, :key], unique: true

    create_table :application_role_assignments do |t|
      t.references :role, null: false, index: false,
                          foreign_key: { to_table: :application_roles, on_delete: :cascade }
      t.references :assignee, null: false, polymorphic: true
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }

      t.timestamps
    end

    add_index :application_role_assignments, [:role_id, :assignee_type, :assignee_id], unique: true,
                                                                                       name: "index_application_role_assignments_uniqueness"
  end

end
