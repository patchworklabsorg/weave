# frozen_string_literal: true

# One master key pair for stored ID images (see KeyCustody). Weave stores
# only the public key. The private key exists only as Shamir shares, one for
# each key holder, each wrapped by that holder's hardware keys.
#
#   pending -> active -> compromised -> retired
#
# - pending: made at a ceremony. It becomes active after a threshold of
#   holders unlock it once, which proves that the shares rebuild the key. A
#   rotation also re-wraps every sealed image of the old set at that time.
# - active: new images are sealed to it.
# - compromised: a holder lost both keys, or the key holder set changed.
#   The set still works, but it must be rotated. The pages show a warning.
# - retired: replaced by a newer set. Its shares are useless.
# == Schema Information
#
# Table name: key_custody_key_sets
# Database name: primary
#
#  id                 :bigint           not null, primary key
#  activated_at       :datetime
#  compromised_at     :datetime
#  compromised_reason :string
#  public_key         :text             not null
#  retired_at         :datetime
#  share_count        :integer          not null
#  status             :string           default("pending"), not null
#  threshold          :integer          not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  created_by_id      :bigint
#  rotated_from_id    :bigint
#
# Indexes
#
#  index_key_custody_key_sets_on_created_by_id    (created_by_id)
#  index_key_custody_key_sets_on_public_key       (public_key) UNIQUE
#  index_key_custody_key_sets_on_rotated_from_id  (rotated_from_id)
#  index_key_custody_key_sets_on_status           (status)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (rotated_from_id => key_custody_key_sets.id)
#
class KeyCustodyKeySet < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :kset

  STATUSES = %w[pending active compromised retired].freeze
  # The set that new images are sealed to.
  CURRENT_STATUSES = %w[active compromised].freeze

  belongs_to :created_by, class_name: "User", optional: true
  belongs_to :rotated_from, class_name: "KeyCustodyKeySet", optional: true
  has_many :shares, class_name: "KeyCustodyShare", foreign_key: :key_set_id, dependent: :restrict_with_exception,
                    inverse_of: :key_set
  has_many :wrapped_shares, through: :shares
  has_many :sealed_documents, class_name: "SealedIdDocument", foreign_key: :key_set_id,
                              dependent: :restrict_with_exception, inverse_of: :key_set
  has_many :sealed_residency_documents, foreign_key: :key_set_id, dependent: :restrict_with_exception,
                                        inverse_of: :key_set

  validates :status, inclusion: { in: STATUSES }
  validates :public_key, presence: true, uniqueness: true
  validates :threshold, numericality: { only_integer: true, greater_than_or_equal_to: 2 }
  validates :share_count, numericality: { only_integer: true, greater_than_or_equal_to: :threshold }
  validate :public_key_length

  scope :current, -> { where(status: CURRENT_STATUSES) }
  scope :pending, -> { where(status: "pending") }

  STATUSES.each { |name| define_method(:"#{name}?") { status == name } }

  def current? = CURRENT_STATUSES.include?(status)

  def rotation? = rotated_from_id.present?

  def public_key_bytes = Base64.strict_decode64(public_key)

  def share_for(user) = shares.find_by(holder_id: user&.id)

  private

  def public_key_length
    errors.add(:public_key, "must be a 32-byte X25519 key") unless public_key_bytes.bytesize == KeyCustody::Crypto::KEY_BYTES
  rescue ArgumentError
    errors.add(:public_key, "must be Base64")
  end

end
