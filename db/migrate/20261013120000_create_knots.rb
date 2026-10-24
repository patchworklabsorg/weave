# frozen_string_literal: true

class CreateKnots < ActiveRecord::Migration[8.1]
  # No timestamps on these tables on purpose: a time is a piece of history.
  # rubocop:disable Rails/CreateTableWithTimestamps
  def change
    # The Knot (see Knot and docs/KYC.md). A Knot holds exactly two pieces of
    # state: the blacklist flag and the program grants received. It has no
    # timestamps and no history. user_id keys it to the member while the
    # account is live. Account deletion empties user_id and keeps the Knot.
    create_table :knots do |t|
      t.references :user, foreign_key: { on_delete: :nullify }, index: { unique: true }
      t.boolean :blacklisted, null: false, default: false
    end

    # The one-way hashes of a Knot. Each digest is a keyed HMAC (see
    # KnotHasher). No identifier is stored in plain text.
    create_table :knot_hashes do |t|
      t.references :knot, null: false, foreign_key: true, index: false
      t.string :kind, null: false
      t.string :digest, null: false
    end
    add_index :knot_hashes, %i[knot_id kind digest], unique: true
    add_index :knot_hashes, %i[kind digest]
    # A strong hash pins one document to one person, so it belongs to one
    # Knot. The soft hash (name and birth date) collides, so many Knots can
    # share it.
    add_index :knot_hashes, %i[kind digest], unique: true, where: "kind <> 'soft'",
                                             name: "index_knot_hashes_on_strong_digest"

    # The program grants a Knot received. Keyed to the Knot, never to the
    # user, so the record survives account deletion.
    create_table :program_grants do |t|
      t.references :knot, null: false, foreign_key: true
      t.string :program, null: false
      t.datetime :granted_at, null: false
    end
    add_index :program_grants, %i[knot_id program]

    # A change to a Knot that waits for a second person's sign-off: the
    # blacklist flag, a legal name change or a grant over the cap. The row is
    # deleted when the change is signed off or declined. The reason lives in
    # the verification audit record (VerificationEvent), never here.
    create_table :knot_change_requests do |t|
      t.references :knot, null: false, foreign_key: true
      # When the audit record expires and is destroyed, a request that waits
      # on it goes too: it has no reason left to sign off.
      t.references :verification, null: false, foreign_key: { on_delete: :cascade }
      t.references :requested_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :kind, null: false
      t.string :program
      t.jsonb :digests, null: false, default: []
      t.datetime :created_at, null: false
    end
  end
  # rubocop:enable Rails/CreateTableWithTimestamps

end
