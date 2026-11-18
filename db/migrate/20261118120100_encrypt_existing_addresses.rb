# frozen_string_literal: true

# Copies each plain-text address value into its Lockbox ciphertext column.
# Lockbox derives the key from the table name, so this local model encrypts
# with the same key as Address. The plain-text columns are not changed.
class EncryptExistingAddresses < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  class MigrationAddress < ActiveRecord::Base
    self.table_name = "addresses"
    self.inheritance_column = nil

    has_encrypted :nickname, :contact_name, :contact_first_name, :contact_last_name, :contact_email,
                  :contact_phone_number, :line1, :line2, :line3, :city, :postal_code, :shipping_notes,
                  migrating: true
    has_encrypted :latitude, :longitude, type: :float, migrating: true

  end

  def up
    MigrationAddress.reset_column_information
    Lockbox.migrate(MigrationAddress, restart: true)
  end

  def down
    # The plain-text columns still hold the values, so there is nothing to undo.
  end

end
