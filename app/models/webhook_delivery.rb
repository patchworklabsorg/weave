# frozen_string_literal: true

# == Schema Information
#
# Table name: webhook_deliveries
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  attempts           :integer          default(0), not null
#  delivered_at       :datetime
#  event              :string           not null
#  last_attempt_at    :datetime
#  payload            :text
#  response           :jsonb            not null
#  status             :string           default("pending"), not null
#  url                :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  event_id           :uuid             not null
#  service_webhook_id :bigint           not null
#  subject_id         :string
#
# Indexes
#
#  index_webhook_deliveries_on_created_at          (created_at)
#  index_webhook_deliveries_on_event_id            (event_id)
#  index_webhook_deliveries_on_service_webhook_id  (service_webhook_id)
#  index_webhook_deliveries_on_subject_id          (subject_id)
#
# Foreign Keys
#
#  fk_rails_...  (service_webhook_id => service_webhooks.id) ON DELETE => cascade
#
# One event sent to one Service::Webhook (see WebhookDispatcher and
# DeliverWebhookJob).
#
# `payload` is the exact request body, so every retry signs the same bytes.
# It holds user data, so it is cleared when the delivery is done (delivered,
# failed or cancelled). The row stays as a log of the attempts and the last
# response until DataRetention::Sweeps removes it after KEEP.
class WebhookDelivery < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :whkdlr

  KEEP = 30.days

  belongs_to :webhook, class_name: "Service::Webhook", foreign_key: :service_webhook_id, inverse_of: :deliveries

  enum :status, {
    pending: "pending", delivered: "delivered", failed: "failed", cancelled: "cancelled"
  }, default: "pending", validate: true

  validates :event, :event_id, :url, presence: true

  scope :expired, -> { where(created_at: ...KEEP.ago) }

  def finish!(status, **attributes)
    update!(status: status, payload: nil, **attributes)
  end

end
