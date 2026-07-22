# frozen_string_literal: true

# == Schema Information
#
# Table name: service_key_usages
# Database name: primary
#
#  id               :bigint           not null, primary key
#  duration_ms      :integer
#  ip_address       :string
#  request_body     :text
#  request_headers  :text
#  request_method   :string
#  request_path     :string
#  requested_at     :datetime
#  response_body    :text
#  response_code    :integer
#  response_headers :text
#  user_agent       :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  service_key_id   :bigint           not null
#  user_id          :integer
#
# Indexes
#
#  index_service_key_usages_on_requested_at                     (requested_at)
#  index_service_key_usages_on_response_code                    (response_code)
#  index_service_key_usages_on_service_key_id                   (service_key_id)
#  index_service_key_usages_on_service_key_id_and_requested_at  (service_key_id,requested_at)
#
# Foreign Keys
#
#  fk_rails_...  (service_key_id => service_keys.id)
#
class Service::Key::Usage < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :sku

  self.table_name = "service_key_usages"

  # Associations
  belongs_to :service_key, class_name: "Service::Key"
  belongs_to :user, optional: true

  # Validations
  validates :request_path, presence: true
  validates :request_method, presence: true

  # Scopes
  scope :recent, -> { order(requested_at: :desc) }
  scope :errors, -> { where("response_code >= ?", 400) }
  scope :successful, -> { where("response_code < ?", 400) }
  scope :slow, ->(threshold_ms = 1000) { where("duration_ms > ?", threshold_ms) }

  # Methods
  def success?
    response_code && response_code < 400
  end

  def error?
    response_code && response_code >= 400
  end

  def slow?(threshold_ms = 1000)
    duration_ms && duration_ms > threshold_ms
  end
end
