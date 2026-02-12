# frozen_string_literal: true

class CreateServiceKeys < ActiveRecord::Migration[8.0]
  def change
    create_table :service_keys do |t|
      t.references :service, null: false, foreign_key: true
      t.string :name, null: false
      t.string :api_key_digest, null: false
      t.string :hash_key, null: false
      t.string :status, null: false, default: "active"
      t.datetime :last_used_at
      t.datetime :expires_at
      t.references :created_by, foreign_key: { to_table: :users }, null: false

      t.timestamps
    end

    add_index :service_keys, :api_key_digest, unique: true
    add_index :service_keys, :status
    add_index :service_keys, [:service_id, :status]
  end
end
