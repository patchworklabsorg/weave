# frozen_string_literal: true

class CreateServiceWebhooks < ActiveRecord::Migration[8.0]
  def change
    create_table :service_webhooks do |t|
      t.references :service, null: false, foreign_key: true
      t.string :url, null: false
      t.string :event_type, null: false
      t.string :secret_token
      t.string :status, null: false, default: "active"
      t.datetime :last_triggered_at
      t.integer :failure_count, default: 0
      t.references :created_by, foreign_key: { to_table: :users }, null: false

      t.timestamps
    end

    add_index :service_webhooks, [:service_id, :event_type]
    add_index :service_webhooks, :status
  end
end
