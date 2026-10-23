# frozen_string_literal: true

class CreateVerificationEvents < ActiveRecord::Migration[8.1]
  def change
    # The append-only audit record of each verification (see
    # VerificationEvent). There is no updated_at: a row never changes. The
    # foreign key to verifications has no cascade, so a verification can't be
    # deleted while its audit rows exist.
    create_table :verification_events do |t|
      t.references :verification, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :kind, null: false
      t.jsonb :data, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :verification_events, :kind
  end

end
