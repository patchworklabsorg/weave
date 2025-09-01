# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[8.0]
    def change
      create_enum 'status', %w[active suspended deactivated]

        create_table :users do |t|
            t.string :first_name, null: false
            t.string :last_name, null: false
            t.string :p_id, null: false
            t.integer :role, null: false, default: 0

            t.string :email, null: false

            t.datetime :acknowledged_over_13_at

            t.datetime :slack_joined_at, null: true
            t.string :slack_id, null: true

            t.string :password_digest, null: false

            t.integer :session_duration_seconds, default: 2592000, null: false

            t.column :status, :status, null: false, default: 'active'
            t.datetime :locked_at
            t.timestamps
        end

        add_index :users, :email, unique: true
        add_index :users, :p_id, unique: true
    end
end
