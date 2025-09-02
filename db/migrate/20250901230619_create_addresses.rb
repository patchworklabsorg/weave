# frozen_string_literal: true

class CreateAddresses < ActiveRecord::Migration[8.0]
  def change
    create_enum 'address_type', ['Venue', 'Shipping', 'Loading Dock']

    create_table :addresses do |t|
      t.string :nickname

      t.string :contact_first_name
      t.string :contact_last_name
      t.string :contact_email
      t.string :contact_phone_number

      t.column :address_type, :address_type, null: false, default: 'Shipping'

      t.string :line1
      t.string :line2
      t.string :line3
      t.string :city
      t.string :state
      t.column :country, 'char(2)'
      t.string :postal_code

      t.float :latitude
      t.float :longitude

      t.boolean :residential, default: false, null: false
      t.boolean :supports_weekend_deliveries, default: false, null: false

      t.references :addressable, polymorphic: true, null: false, type: :uuid

      t.timestamps
    end

    add_index :addresses, :addressable_id
    add_index :addresses, :addressable_type
  end
end
