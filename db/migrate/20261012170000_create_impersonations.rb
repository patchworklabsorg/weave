# frozen_string_literal: true

class CreateImpersonations < ActiveRecord::Migration[8.1]
  def change
    # One row per impersonation an admin started, or tried to start. The rows
    # outlive the accounts: deleting either user keeps the row and clears the
    # reference, so the audit trail is not lost.
    create_table :impersonations do |t|
      t.references :admin, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :user, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.string :end_reason
      t.boolean :denied, default: false, null: false
      t.string :ip
      t.string :user_agent
      t.timestamps
    end
  end

end
