# frozen_string_literal: true

class CreateGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :groups do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :kind, null: false, default: "manual"
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :deleted_at

      t.timestamps
    end

    # A deleted group frees its name and slug for a new group.
    add_index :groups, :slug, unique: true, where: "deleted_at IS NULL"
    add_index :groups, :name, unique: true, where: "deleted_at IS NULL"
    add_index :groups, :deleted_at

    create_table :group_memberships do |t|
      t.references :group, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.references :added_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :source, null: false, default: "manual"
      t.datetime :expires_at

      t.timestamps
    end

    add_index :group_memberships, [:group_id, :user_id], unique: true
    add_index :group_memberships, :expires_at, where: "expires_at IS NOT NULL"
  end
end
