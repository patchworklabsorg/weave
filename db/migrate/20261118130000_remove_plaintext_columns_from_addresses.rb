# frozen_string_literal: true

# The second step of address encryption. EncryptExistingAddresses copied each
# plain-text value into its Lockbox ciphertext column, and Address has ignored
# the plain-text columns since then. This drops them, so the addresses table
# holds no street, postal code, contact or coordinate in plain text.
#
# Back up the database and check the backfill before this runs in production:
# every address with a line1 must have a line1_ciphertext.
class RemovePlaintextColumnsFromAddresses < ActiveRecord::Migration[8.1]
  COLUMNS = {
    nickname: :string, contact_name: :string, contact_first_name: :string, contact_last_name: :string,
    contact_email: :string, contact_phone_number: :string, line1: :string, line2: :string, line3: :string,
    city: :string, postal_code: :string, shipping_notes: :text, latitude: :float, longitude: :float
  }.freeze

  def up
    missing = select_value(<<~SQL.squish)
      SELECT count(*) FROM addresses
      WHERE (line1 IS NOT NULL AND line1_ciphertext IS NULL)
         OR (postal_code IS NOT NULL AND postal_code_ciphertext IS NULL)
         OR (city IS NOT NULL AND city_ciphertext IS NULL)
    SQL
    raise "#{missing} addresses have plain text but no ciphertext. Run EncryptExistingAddresses first." if missing.to_i.positive?

    safety_assured do
      COLUMNS.each_key { |name| remove_column :addresses, name }
    end
  end

  # The values are gone. This brings back empty columns only.
  def down
    COLUMNS.each { |name, type| add_column :addresses, name, type }
  end

end
