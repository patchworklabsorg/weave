# frozen_string_literal: true

class CreateKeyCustody < ActiveRecord::Migration[8.1]
  def change
    # The hardware keys (YubiKeys) of a key holder, registered with WebAuthn.
    # Each holder has a primary and a backup key.
    create_table :identity_hardware_keys do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :external_id, null: false
      t.text :public_key, null: false
      t.bigint :sign_count, null: false, default: 0
      t.string :role, null: false
      t.string :nickname
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.references :revoked_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.text :revoked_reason
      # The PRF salt of this key's seal key. In the holder's own browser,
      # HKDF(PRF output) gives an X25519 key pair. Weave stores only the
      # public key (seal_public_key). A share is sealed to it at the ceremony.
      t.string :seal_salt, null: false
      t.string :seal_public_key
      t.timestamps
    end
    add_index :identity_hardware_keys, :external_id, unique: true

    # One master key pair. Weave stores only the public key. The private key
    # exists only as Shamir shares, each wrapped by a holder's hardware keys.
    create_table :key_custody_key_sets do |t|
      t.text :public_key, null: false
      t.integer :threshold, null: false
      t.integer :share_count, null: false
      t.string :status, null: false, default: "pending"
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :rotated_from, foreign_key: { to_table: :key_custody_key_sets }
      t.datetime :activated_at
      t.datetime :compromised_at
      t.string :compromised_reason
      t.datetime :retired_at
      t.timestamps
    end
    add_index :key_custody_key_sets, :public_key, unique: true
    add_index :key_custody_key_sets, :status

    # The share of one holder in one key set: its x value and a digest. The
    # share itself is never stored.
    create_table :key_custody_shares do |t|
      t.references :key_set, null: false, foreign_key: { to_table: :key_custody_key_sets }
      t.references :holder, foreign_key: { to_table: :users, on_delete: :nullify }
      t.integer :x, null: false
      t.string :digest, null: false
      t.timestamps
    end
    add_index :key_custody_shares, [:key_set_id, :holder_id], unique: true
    add_index :key_custody_shares, [:key_set_id, :x], unique: true

    # A share sealed to the seal public key of one hardware key (X25519,
    # HKDF-SHA256, AES-256-GCM). Only that key's PRF output, in its holder's
    # browser, opens it. Weave can't open it.
    create_table :key_custody_wrapped_shares do |t|
      t.references :share, null: false, foreign_key: { to_table: :key_custody_shares, on_delete: :cascade }
      t.references :hardware_key, null: false, foreign_key: { to_table: :identity_hardware_keys, on_delete: :cascade }
      t.text :sealed, null: false
      t.timestamps
    end
    add_index :key_custody_wrapped_shares, [:share_id, :hardware_key_id], unique: true

    # A share that waits for the next share of the same request or
    # activation (see KeyCustody::PendingShares). It is in the database, so
    # every web process sees it. It is encrypted with Lockbox and bound to
    # its memory_key, and it is deleted when the shares are combined, on a
    # deny, and after pending_share_minutes (SweepPendingSharesJob). One share
    # alone reveals nothing about the master key.
    create_table :key_custody_pending_shares do |t|
      t.string :memory_key, null: false
      t.references :holder, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      t.text :share_ciphertext, null: false
      t.datetime :expires_at, null: false
      t.datetime :created_at, null: false
    end
    add_index :key_custody_pending_shares, [:memory_key, :holder_id], unique: true
    add_index :key_custody_pending_shares, :expires_at

    # A WebAuthn challenge for one purpose and one subject (for example one
    # break-glass request). Each challenge works once.
    create_table :key_custody_challenges do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :purpose, null: false
      t.string :subject, null: false
      t.string :challenge, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.datetime :created_at, null: false
    end
    add_index :key_custody_challenges, :challenge, unique: true

    # The append-only log of key custody: ceremonies, keys, recovery and
    # rotation.
    create_table :key_custody_events do |t|
      t.string :kind, null: false
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :subject, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :key_set, foreign_key: { to_table: :key_custody_key_sets }
      t.jsonb :data, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :key_custody_events, :created_at

    # An ID image sealed after pre-review: the image encrypted with a data
    # key, and the data key sealed to the master public key of a key set.
    create_table :sealed_id_documents do |t|
      t.references :verification, null: false, foreign_key: true, index: { unique: true }
      t.references :key_set, null: false, foreign_key: { to_table: :key_custody_key_sets }
      t.text :sealed_data_key, null: false
      t.string :content_type, null: false
      t.string :extension
      t.datetime :sealed_at, null: false
      t.timestamps
    end

    # The break-glass tables are new in this unreleased stack and have no
    # rows, so the changes below lock nothing that matters.
    safety_assured do
      # The key set whose shares opened the image. Weave keeps no data key
      # after the request: the image is decrypted in the request of the
      # second share, and everything is wiped.
      add_reference :break_glass_records, :key_set, foreign_key: { to_table: :key_custody_key_sets }, index: true

      # An approval is the submission of a share with a hardware key. A share
      # waits for at most pending_share_minutes, so it can lapse before the
      # second share comes. Then the holder submits again.
      add_reference :break_glass_approvals, :hardware_key,
                    foreign_key: { to_table: :identity_hardware_keys, on_delete: :nullify }, index: true
      add_column :break_glass_approvals, :lapsed_at, :datetime
      remove_index :break_glass_approvals, [:break_glass_record_id, :approver_id],
                   unique: true, name: "index_break_glass_approvals_on_record_and_approver"
      add_index :break_glass_approvals, [:break_glass_record_id, :approver_id],
                unique: true, where: "lapsed_at IS NULL", name: "index_break_glass_approvals_on_record_and_approver"
    end
  end

end
