# frozen_string_literal: true

# Data handling, takeout and deletion (proposal v0.8 section 06, issue #94).
# See DataCategories, DeletionPipeline and docs/KYC.md.
class CreateDataHandling < ActiveRecord::Migration[8.1]
  def change
    # The member's part in a program: one row per program and year. Only the
    # generalized bands leave this table at deletion (DeleteTimeAggregates).
    # A row stays after the account is deleted only when the program's funder
    # requires individual records, and only until retained_until.
    create_table :program_participations do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :program, null: false
      t.integer :year, null: false
      t.string :outcome, null: false
      t.string :funder
      # Filled only when the row is kept after deletion, because the user row
      # (birthday, address) is gone then.
      t.string :age_band
      t.string :region
      t.string :amount_band
      t.datetime :detached_at
      t.datetime :retained_until
      t.timestamps
    end
    add_index :program_participations, %i[user_id program year], unique: true, where: "user_id IS NOT NULL"
    add_index :program_participations, :retained_until

    # Grant money paid to a member. Kept under the IRS, audit and funder
    # obligation (config/kyc/data_retention.yml), then anonymized: the person's
    # details go, the amount, the program and the year stay.
    create_table :grant_disbursements do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :program, null: false
      t.string :funder
      t.date :disbursed_on, null: false
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "USD"
      t.text :payee_name_ciphertext
      t.text :payee_email_ciphertext
      t.text :reference_ciphertext
      t.datetime :detached_at
      t.datetime :anonymized_at
      t.timestamps
    end
    add_index :grant_disbursements, :disbursed_on

    # Running totals of departed members. No row per person, no identifier
    # and no timestamps. A random id, so the row order does not tell when a
    # row was added. Reports read them through small-count suppression.
    create_table :delete_time_aggregates, id: :uuid do |t| # rubocop:disable Rails/CreateTableWithTimestamps
      t.string :program, null: false
      t.integer :year, null: false
      t.string :outcome, null: false
      t.string :age_band, null: false
      t.string :region, null: false
      t.string :amount_band, null: false
      t.integer :count, null: false, default: 0
    end
    add_index :delete_time_aggregates, %i[program year outcome age_band region amount_band],
              unique: true, name: "index_delete_time_aggregates_on_bands"

    # A request to delete an account. A human on the identity team reviews
    # every request (an authenticity check) before the pipeline runs.
    create_table :deletion_requests do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :source, null: false, default: "member"
      t.string :status, null: false, default: "pending_review"
      t.datetime :requested_at, null: false
      t.datetime :review_due_at, null: false
      t.datetime :complete_by, null: false
      t.references :reviewed_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :reviewed_at
      t.text :review_note
      # Where the receipt goes. Emptied after the receipt is sent.
      t.text :receipt_email_ciphertext
      # What was removed and what was retained, by category. No values.
      t.jsonb :receipt, null: false, default: {}
      t.datetime :receipt_sent_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :deletion_requests, :status

    # Every run of the deletion pipeline, with each step.
    create_table :deletion_runs do |t| # rubocop:disable Rails/CreateTableWithTimestamps
      t.references :deletion_request, null: false, foreign_key: { on_delete: :cascade }
      t.string :outcome, null: false, default: "running"
      t.jsonb :steps, null: false, default: []
      t.string :error_class
      t.text :error_message
      t.datetime :started_at, null: false
      t.datetime :finished_at
    end

    # A member's data export (takeout). The JSON file is an encrypted Active
    # Storage attachment.
    create_table :takeout_requests do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :status, null: false, default: "pending"
      t.datetime :ready_at
      t.datetime :expires_at
      t.datetime :downloaded_at
      t.timestamps
    end

    # The warnings before the dormancy cutoff. last_active_at is the activity
    # the warning was for: a sign-in moves it, so old warnings stop counting.
    create_table :dormancy_warnings do |t| # rubocop:disable Rails/CreateTableWithTimestamps
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.integer :days_before, null: false
      t.datetime :last_active_at, null: false
      t.datetime :sent_at, null: false
    end
    add_index :dormancy_warnings, %i[user_id days_before last_active_at], unique: true,
                                                                          name: "index_dormancy_warnings_unique"

    # Starts the retention window of the verification audit records. The
    # table is new in this release, so the column and the index do not block
    # writes.
    safety_assured do
      add_column :verifications, :account_deleted_at, :datetime
      add_index :verifications, :account_deleted_at
    end
  end

end
