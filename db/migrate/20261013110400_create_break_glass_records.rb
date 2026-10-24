# frozen_string_literal: true

class CreateBreakGlassRecords < ActiveRecord::Migration[8.1]
  def change
    # Break-glass access to a stored ID image (see BreakGlassRecord): a
    # request with a reason, approved by two different key holders. Each
    # decryption is its own row, and each decryption creates its notices.
    create_table :break_glass_records do |t|
      t.references :verification, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.references :requested_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.text :reason, null: false
      t.datetime :granted_at
      t.datetime :expires_at
      t.datetime :denied_at
      t.references :denied_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.text :denial_reason
      t.timestamps
    end

    create_table :break_glass_approvals do |t|
      t.references :break_glass_record, null: false, foreign_key: true
      t.references :approver, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :created_at, null: false
    end
    add_index :break_glass_approvals, [:break_glass_record_id, :approver_id],
              unique: true, name: "index_break_glass_approvals_on_record_and_approver"

    create_table :break_glass_decryptions do |t|
      t.references :break_glass_record, null: false, foreign_key: true
      t.references :viewer, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :ip
      t.string :user_agent
      t.datetime :created_at, null: false
    end

    create_table :break_glass_notices do |t|
      t.references :break_glass_decryption, null: false, foreign_key: true
      t.references :recipient, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :recipient_kind, null: false
      t.datetime :due_at, null: false
      t.datetime :sent_at
      t.datetime :delayed_at
      t.references :delayed_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.text :delay_reason
      t.datetime :delay_lifted_at
      t.references :delay_lifted_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :break_glass_notices, [:sent_at, :due_at]
  end

end
