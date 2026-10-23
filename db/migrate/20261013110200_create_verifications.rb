# frozen_string_literal: true

class CreateVerifications < ActiveRecord::Migration[8.1]
  def change
    # One row per verification attempt (see Verification). Each attempt links
    # to the one before it, so the history of a member reads as one chain.
    # The call is never recorded: there are no video or recording columns.
    # Identifiers from the ID (document number, name, birth date) are never
    # stored (see VerificationIdentifiers).
    create_table :verifications do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.references :previous_attempt, foreign_key: { to_table: :verifications, on_delete: :nullify }
      t.string :verification_method, null: false, default: "document_call"
      t.string :status, null: false, default: "submitted"
      t.string :document_type

      t.references :pre_reviewer, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :pre_review_started_at
      t.datetime :pre_reviewed_at
      t.text :resubmission_note

      t.datetime :call_scheduled_for
      t.references :call_scheduled_by, foreign_key: { to_table: :users, on_delete: :nullify }

      t.references :verifier, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :second_verifier, foreign_key: { to_table: :users, on_delete: :nullify }
      t.boolean :guardian_attended, null: false, default: false
      t.references :guardian_consent, foreign_key: { on_delete: :nullify }
      t.boolean :age_consistent
      t.boolean :region_consistent
      t.text :decision_reason
      t.datetime :decided_at

      t.datetime :escalated_at
      t.datetime :escalation_resolved_at
      t.references :escalation_resolved_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :escalation_resolution
      t.text :escalation_note

      t.datetime :document_purged_at

      # A pass has no time limit. A trigger (a birthday change, a legal name
      # change or a blacklist review) marks it as no longer standing, and the
      # member then needs a new call (see VerificationFlow.require_reverification).
      t.datetime :reverification_required_at
      t.string :reverification_reason
      t.timestamps
    end
    add_index :verifications, :status
  end

end
