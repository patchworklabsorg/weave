# frozen_string_literal: true

# A production console waits for a superadmin to approve it in Weave. See
# ConsoleAccessRequest and docs/CONSOLE_ACCESS.md.
class CreateConsoleAccessRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :console_access_requests do |t|
      t.string :kind, null: false
      t.string :code_digest, null: false
      t.string :host
      t.string :status, null: false, default: "pending"
      t.datetime :expires_at, null: false
      t.references :decided_by, foreign_key: { to_table: :users }
      t.datetime :decided_at
      t.datetime :claimed_at

      t.timestamps
    end
    add_index :console_access_requests, :code_digest, unique: true
  end

end
