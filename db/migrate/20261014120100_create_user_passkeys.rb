# frozen_string_literal: true

class CreateUserPasskeys < ActiveRecord::Migration[8.1]
  def change
    create_table :user_passkeys do |t|
      t.references :user, null: false, foreign_key: true
      # The credential id and the COSE public key, both base64url, as the
      # webauthn gem gives them.
      t.string :external_id, null: false
      t.text :public_key, null: false
      t.bigint :sign_count, null: false, default: 0
      t.string :nickname
      t.datetime :last_used_at
      # Set when the sign count goes back, which can mean a cloned key. A
      # compromised passkey cannot sign in.
      t.datetime :compromised_at
      t.timestamps
    end

    add_index :user_passkeys, :external_id, unique: true
  end

end
