# frozen_string_literal: true

# Postal addresses are personal data. The street, the postal code, the contact
# details and the coordinates move to Lockbox ciphertext columns. state and
# country stay in plain text, because residency checks and aggregates read them.
# The plain-text columns stay until a later migration drops them; the model
# ignores them from now on.
class AddCiphertextColumnsToAddresses < ActiveRecord::Migration[8.1]
  COLUMNS = %i[nickname contact_name contact_first_name contact_last_name contact_email contact_phone_number line1
               line2 line3 city postal_code shipping_notes latitude longitude].freeze

  def up
    COLUMNS.each { |name| add_column :addresses, :"#{name}_ciphertext", :text }
  end

  # After the new code runs, the ciphertext is the only copy of a new or edited
  # address. Dropping these columns would lose it.
  def down
    raise ActiveRecord::IrreversibleMigration
  end

end
