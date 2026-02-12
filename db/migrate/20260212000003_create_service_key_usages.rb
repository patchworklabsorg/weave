# frozen_string_literal: true

class CreateServiceKeyUsages < ActiveRecord::Migration[8.0]
  def change
    create_table :service_key_usages do |t|
      t.references :service_key, null: false, foreign_key: true
      t.string :request_path
      t.string :request_method
      t.integer :response_code
      t.integer :duration_ms
      t.string :ip_address
      t.string :user_agent
      t.text :request_headers
      t.text :request_body
      t.text :response_headers
      t.text :response_body
      t.integer :user_id
      t.datetime :requested_at

      t.timestamps
    end

    add_index :service_key_usages, :service_key_id
    add_index :service_key_usages, :requested_at
    add_index :service_key_usages, :response_code
    add_index :service_key_usages, [:service_key_id, :requested_at]
  end
end
