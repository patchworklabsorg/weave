# frozen_string_literal: true

class CreateIdentityGovernance < ActiveRecord::Migration[8.1]
  def change
    # A signed NDA, recorded by hand by an owner (see IdentityNda). NDAs are
    # signed with Adobe Acrobat Sign, so the row holds only the date, the
    # version and the agreement ID. Rows are append-only: a newer row
    # supersedes an older one.
    create_table :identity_ndas do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.date :signed_on, null: false
      t.string :nda_version, null: false
      t.string :signature_reference, null: false
      t.references :recorded_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :created_at, null: false
    end

    # A change to the identity team that needs approval (see
    # IdentityGovernance): add a verifier, set or clear the lead, add or remove
    # a key holder.
    create_table :identity_governance_proposals do |t|
      t.string :kind, null: false
      t.string :status, null: false, default: "pending"
      t.references :subject, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :proposed_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.text :reason, null: false
      # For a key holder change: every board member at proposal time.
      t.bigint :required_approver_ids, array: true, null: false, default: []
      t.datetime :expires_at, null: false
      t.datetime :closed_at
      t.references :closed_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.text :close_reason
      t.timestamps
    end
    add_index :identity_governance_proposals, [:status, :expires_at]

    create_table :identity_governance_approvals do |t|
      t.references :identity_governance_proposal, null: false, foreign_key: true,
                                                  index: { name: "index_identity_governance_approvals_on_proposal" }
      t.references :approver, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :created_at, null: false
    end
    add_index :identity_governance_approvals, [:identity_governance_proposal_id, :approver_id],
              unique: true, name: "index_identity_governance_approvals_on_proposal_and_approver"

    # The append-only log of every governance step (see
    # IdentityGovernanceEvent).
    create_table :identity_governance_events do |t|
      t.string :kind, null: false
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :subject, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :identity_governance_proposal, foreign_key: { on_delete: :nullify },
                                                  index: { name: "index_identity_governance_events_on_proposal" }
      t.jsonb :data, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :identity_governance_events, :created_at
  end

end
