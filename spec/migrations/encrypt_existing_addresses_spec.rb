# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261118120100_encrypt_existing_addresses")

# The data migration: each plain-text address value is copied into its Lockbox
# ciphertext column, and Address decrypts it with its own key.
RSpec.describe EncryptExistingAddresses do
  delegate :connection, to: :'ActiveRecord::Base'

  def migrate = ActiveRecord::Migration.suppress_messages { described_class.new.migrate(:up) }

  # Address ignores the plain-text columns, so set them with SQL, and clear the
  # ciphertext the factory wrote, as rows from before the migration have none.
  def set_plaintext(address, **columns)
    assignments = columns.map { |column, value| "#{column} = #{connection.quote(value)}" }
    clears = Address::ENCRYPTED_FIELDS.chain(Address::ENCRYPTED_COORDINATES).map { |column| "#{column}_ciphertext = NULL" }
    connection.execute("UPDATE addresses SET #{(assignments + clears).join(', ')} WHERE id = #{address.id}")
  end

  it "encrypts the plain-text values and keeps the plain-text columns" do
    address = create(:shipping_address)
    set_plaintext(address, line1: "1 Main St", line2: nil, city: "Burlington", postal_code: "05401",
                           contact_name: "Ada", contact_email: "ada@patchworklabs.org", shipping_notes: "Back door",
                           latitude: 44.47, longitude: -73.21)

    migrate

    expect(Address.find(address.id)).to have_attributes(
      line1: "1 Main St", line2: nil, city: "Burlington", postal_code: "05401", contact_name: "Ada",
      contact_email: "ada@patchworklabs.org", shipping_notes: "Back door", latitude: 44.47, longitude: -73.21,
      state: "IL"
    )
    expect(connection.select_value("SELECT line1 FROM addresses WHERE id = #{address.id}")).to eq("1 Main St")
  end

  it "leaves a row that the new code wrote alone on a second run" do
    address = create(:shipping_address, line1: "2 Elm St")

    migrate

    expect(Address.find(address.id).line1).to eq("2 Elm St")
  end

  it "keeps the address fields out of the log" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    params = {
      "shipping_address_attributes" => { "line1" => "1 Main St" },
      "billing_address_attributes"  => { "postal_code" => "05401" }
    }

    expect(filter.filter("user" => params))
      .to eq("user" => { "shipping_address_attributes" => "[FILTERED]", "billing_address_attributes" => "[FILTERED]" })
  end
end
