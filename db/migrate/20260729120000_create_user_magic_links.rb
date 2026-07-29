# frozen_string_literal: true

class CreateUserMagicLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :user_magic_links do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.string :requested_ip
      t.timestamps

      t.index :token_digest, unique: true
      t.index :expires_at
    end
  end

end
