# frozen_string_literal: true

# The US residency check (see ResidencyCheck and docs/KYC.md). Each row is one
# check: on the identity call, or a document review without a call. Only the
# result, the US state, the evidence type and the dates are kept. A proof
# document is sealed like an ID image and purged on the same schedule.
class CreateResidencyChecks < ActiveRecord::Migration[8.1]
  def change
    create_table :residency_checks do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      # The identity attempt, when the check was part of its call.
      t.references :verification, foreign_key: { on_delete: :nullify }
      t.string :source, null: false
      t.string :status, null: false, default: "submitted"
      t.string :evidence_type, null: false
      t.boolean :us_resident
      t.string :us_state, limit: 2
      t.references :pre_reviewer, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :pre_review_started_at
      t.datetime :pre_reviewed_at
      t.text :resubmission_note
      t.references :decided_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :decided_at
      t.datetime :ended_at
      t.string :end_reason
      t.datetime :renewal_reminded_at
      t.datetime :document_purged_at
      t.datetime :account_deleted_at

      t.timestamps
    end
    add_index :residency_checks, :status
    add_index :residency_checks, :decided_at

    # A proof document after pre-review, sealed like an ID image (see
    # ResidencyDocumentVault).
    create_table :sealed_residency_documents do |t|
      t.references :residency_check, null: false, index: { unique: true }, foreign_key: true
      t.references :key_set, null: false, foreign_key: { to_table: :key_custody_key_sets }
      t.text :sealed_data_key, null: false
      t.string :content_type, null: false
      t.string :extension
      t.datetime :sealed_at, null: false

      t.timestamps
    end
  end

end
