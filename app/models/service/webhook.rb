# frozen_string_literal: true

# == Schema Information
#
# Table name: service_webhooks
# Database name: primary
#
#  id                :bigint           not null, primary key
#  event_type        :string           not null
#  failure_count     :integer          default(0)
#  last_triggered_at :datetime
#  secret_token      :string
#  status            :string           default("active"), not null
#  url               :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  created_by_id     :bigint           not null
#  service_id        :bigint           not null
#
# Indexes
#
#  index_service_webhooks_on_created_by_id              (created_by_id)
#  index_service_webhooks_on_service_id                 (service_id)
#  index_service_webhooks_on_service_id_and_event_type  (service_id,event_type)
#  index_service_webhooks_on_status                     (status)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (service_id => services.id)
#
class Service::Webhook < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :swh

  self.table_name = "service_webhooks"

  # Associations
  belongs_to :service
  belongs_to :created_by, class_name: "User"
  has_many :deliveries, class_name: "WebhookDelivery", foreign_key: :service_webhook_id,
                        inverse_of: :webhook, dependent: :delete_all

  # Validations
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :event_type, presence: true, inclusion: { in: ->(_) { EVENT_TYPES } }
  validate :url_uses_https, if: -> { WebhookUrlGuard.https_only? }
  validates :status, presence: true, inclusion: { in: %w[active inactive] }

  # Callbacks
  before_create :generate_secret_token

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :inactive, -> { where(status: "inactive") }
  scope :for_event, ->(event_type) { where(event_type: event_type) }
  # Active webhooks of active services: the ones that get deliveries.
  scope :deliverable, -> { active.joins(:service).merge(Service.active) }

  # Constants
  EVENT_TYPES = %w[
    user.created
    user.updated
    user.deleted
    session.created
    session.expired
    group.member_added
    group.member_removed
  ].freeze

  # Methods
  def active?
    status == "active"
  end

  def inactive?
    status == "inactive"
  end

  def activate!
    update!(status: "active", failure_count: 0)
  end

  # Queued deliveries are cancelled: they would not be sent anyway.
  def deactivate!
    transaction do
      update!(status: "inactive")
      deliveries.pending.find_each { |delivery| delivery.finish!("cancelled") }
    end
  end

  def rotate_secret!
    update!(secret_token: SecureRandom.hex(32))
  end

  def record_trigger!
    update!(last_triggered_at: Time.current)
  end

  def record_failure!
    increment!(:failure_count)
    deactivate! if failure_count >= 10
  end

  def reset_failures!
    update!(failure_count: 0)
  end

  private

  def url_uses_https
    errors.add(:url, "must use https") unless url.to_s.start_with?("https://")
  end

  def generate_secret_token
    self.secret_token ||= SecureRandom.hex(32)
  end

end
