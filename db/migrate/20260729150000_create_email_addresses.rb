# frozen_string_literal: true

class CreateEmailAddresses < ActiveRecord::Migration[8.1]
  def change
    create_table :email_addresses do |t|
      t.references :user, null: false, foreign_key: true
      t.string :email, null: false
      t.boolean :is_primary, default: false, null: false
      t.datetime :confirmed_at
      t.string :confirmation_token
      t.datetime :confirmation_sent_at

      t.timestamps
    end

    add_index :email_addresses, :email, unique: true
    add_index :email_addresses, :confirmation_token, unique: true
    # Exactly one primary email address per user.
    add_index :email_addresses, :user_id, unique: true, where: "is_primary",
                                          name: "index_email_addresses_one_primary_per_user"
  end
end
