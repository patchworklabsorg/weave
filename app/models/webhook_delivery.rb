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
class WebhookDelivery < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :whkdlr

end
