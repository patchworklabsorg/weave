# frozen_string_literal: true

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
