# frozen_string_literal: true

class CreateThreadCountEntries < ActiveRecord::Migration[8.1]
  def change
    # The Thread Count (TC) ledger: the internal trust score of a member (see
    # ThreadCount::Entry). Append-only. Rows are never changed: a withdrawn or
    # wrong entry gets a "reversal" row that points at it. The score is
    # computed from these rows (see ThreadCount.score) and is not stored.
    create_table :thread_count_entries do |t|
      # The member the entry is about. The ledger goes with the account.
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      # The weight row in config/thread_count.yml: the voucher's tier for a
      # staff vouch, the severity of a moderation case, the signal name of an
      # external signal. Empty for the other kinds.
      t.string :level

      # The person who puts their name on the entry (the voucher, or the staff
      # member who records a deduction).
      t.references :author, foreign_key: { to_table: :users, on_delete: :nullify }
      # The staff member who typed it in. Empty when a service sent it.
      t.references :recorded_by, foreign_key: { to_table: :users, on_delete: :nullify }
      # The service that sent it (project events from Krater and others).
      t.references :service, foreign_key: { on_delete: :nullify }

      # Encrypted with Lockbox: free text about a member.
      t.text :reason_ciphertext
      t.text :evidence_url_ciphertext
      t.references :evidence, polymorphic: true

      # The service's own ID for the project, so a retried event is not
      # counted twice.
      t.string :project_ref

      # Set on a "reversal" row: the entry it cancels.
      t.references :reverses, foreign_key: { to_table: :thread_count_entries, on_delete: :cascade },
                              index: { unique: true }

      t.datetime :created_at, null: false
    end

    add_index :thread_count_entries, [:user_id, :kind]
    add_index :thread_count_entries, [:service_id, :project_ref, :kind], unique: true,
                                                                         where: "project_ref IS NOT NULL",
                                                                         name: "index_thread_count_entries_on_project_event"
  end

end
