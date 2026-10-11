# frozen_string_literal: true

class CreateGuardianConsents < ActiveRecord::Migration[8.1]
  def change
    # A parent or guardian's consent for a member under 18 (see
    # GuardianConsent). One row per request, so the history of sends, grants
    # and revocations is kept.
    create_table :guardian_consents do |t|
      t.references :user, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"

      # Encrypted with Lockbox.
      t.text :guardian_name_ciphertext
      t.text :guardian_email_ciphertext
      t.text :signed_name_ciphertext

      # Only a SHA-256 digest of the link token is kept. Offline consent,
      # recorded by an admin, has no link.
      t.string :token_digest, index: { unique: true }
      t.datetime :sent_at
      t.datetime :expires_at

      t.datetime :granted_at
      t.string :granted_ip
      t.string :granted_user_agent
      t.string :text_version

      t.datetime :revoked_at
      t.references :revoked_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.references :recorded_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.text :note

      t.timestamps
    end
  end

end
