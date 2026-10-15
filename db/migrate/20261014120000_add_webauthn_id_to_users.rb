# frozen_string_literal: true

class AddWebauthnIdToUsers < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # The WebAuthn user handle. A passkey stores it and gives it back at sign-in,
  # so it must be random and stable, and must not contain the email or the id.
  # It is set the first time the user adds a passkey.
  def change
    add_column :users, :webauthn_id, :string
    add_index :users, :webauthn_id, unique: true, algorithm: :concurrently
  end

end
