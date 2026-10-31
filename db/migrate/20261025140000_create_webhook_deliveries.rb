# frozen_string_literal: true

# The WebhookDelivery model shipped without a table. Each row is one event
# sent to one Service::Webhook, with its attempts and the last response.
class CreateWebhookDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :webhook_deliveries do |t|
      t.references :service_webhook, null: false, foreign_key: { on_delete: :cascade }
      t.string :event, null: false
      t.uuid :event_id, null: false
      # The p_id of the user the event is about, so an account deletion can
      # cancel what is still queued for that user.
      t.string :subject_id
      t.string :url, null: false
      t.text :payload
      t.string :status, null: false, default: "pending"
      t.integer :attempts, null: false, default: 0
      t.datetime :last_attempt_at
      t.datetime :delivered_at
      t.jsonb :response, null: false, default: {}

      t.timestamps
    end

    add_index :webhook_deliveries, :event_id
    add_index :webhook_deliveries, :subject_id
    add_index :webhook_deliveries, :created_at
  end

end
