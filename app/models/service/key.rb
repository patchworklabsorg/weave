# frozen_string_literal: true

# == Schema Information
#
# Table name: service_keys
# Database name: primary
#
#  id             :bigint           not null, primary key
#  api_key_digest :string           not null
#  expires_at     :datetime
#  hash_key       :string           not null
#  last_used_at   :datetime
#  name           :string           not null
#  status         :string           default("active"), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  created_by_id  :bigint           not null
#  service_id     :bigint           not null
#
# Indexes
#
#  index_service_keys_on_api_key_digest         (api_key_digest) UNIQUE
#  index_service_keys_on_created_by_id          (created_by_id)
#  index_service_keys_on_service_id             (service_id)
#  index_service_keys_on_service_id_and_status  (service_id,status)
#  index_service_keys_on_status                 (status)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (service_id => services.id)
#
class Service::Key < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :skey

  self.table_name = "service_keys"

  # Associations
  belongs_to :service
  belongs_to :created_by, class_name: "User"
  has_many :usages, class_name: "Service::Key::Usage", dependent: :destroy

  # Validations
  validates :name, presence: true
  validates :status, presence: true, inclusion: { in: %w[active deprecated revoked] }
  validates :api_key_digest, presence: true, uniqueness: true
  validates :hash_key, presence: true

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :deprecated, -> { where(status: "deprecated") }
  scope :revoked, -> { where(status: "revoked") }
  scope :usable, -> { where(status: %w[active deprecated]) }

  # Callbacks
  before_create :generate_hash_key

  # Class methods
  def self.generate_api_key
    "pwl_#{SecureRandom.urlsafe_base64(32)}"
  end

  def self.find_by_api_key(api_key)
    return nil if api_key.blank?

    digest = Digest::SHA256.hexdigest(api_key)
    find_by(api_key_digest: digest)
  end

  # Instance methods
  def active?
    status == "active"
  end

  def deprecated?
    status == "deprecated"
  end

  def revoked?
    status == "revoked"
  end

  def may_use?
    (active? || deprecated?) && !expired?
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def activate!
    update!(status: "active")
  end

  def deprecate!
    update!(status: "deprecated")
  end

  def revoke!
    update!(status: "revoked")
  end

  def record_usage!
    update!(last_used_at: Time.current)
  end

  # Set the API key (only on creation)
  # Returns the plaintext API key (only time it's available)
  def api_key=(value)
    @api_key = value
    self.api_key_digest = Digest::SHA256.hexdigest(value)
  end

  def api_key
    @api_key
  end

  private

  def generate_hash_key
    self.hash_key ||= SecureRandom.hex(32)
  end
end
