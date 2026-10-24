# frozen_string_literal: true

# A hardware key (YubiKey) of a break-glass key holder, registered with
# WebAuthn (see KeyCustody). Each holder has a primary key and a backup key.
# The key opens the holder's share of the master key through the WebAuthn
# PRF extension, in the holder's browser only: the PRF output for seal_salt
# gives an X25519 seal key pair (HKDF), and a share is sealed to its public
# key (seal_public_key). Weave never has the seal private key. The holder
# registers the public key from their own computer, with an assertion of the
# key, right after enrollment (KeyCustody::Enrollment.register_seal_key!).
#
# A revoked key stays as a record. Its wrapped shares are deleted, so the
# key can't open a share again, also when somebody finds it.
# == Schema Information
# Schema version: 20261023120000
#
# Table name: identity_hardware_keys
# Database name: primary
#
#  id              :bigint           not null, primary key
#  last_used_at    :datetime
#  nickname        :string
#  public_key      :text             not null
#  revoked_at      :datetime
#  revoked_reason  :text
#  role            :string           not null
#  seal_public_key :string
#  seal_salt       :string           not null
#  sign_count      :bigint           default(0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  external_id     :string           not null
#  revoked_by_id   :bigint
#  user_id         :bigint           not null
#
# Indexes
#
#  index_identity_hardware_keys_on_external_id    (external_id) UNIQUE
#  index_identity_hardware_keys_on_revoked_by_id  (revoked_by_id)
#  index_identity_hardware_keys_on_user_id        (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (revoked_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
class IdentityHardwareKey < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :hwk

  ROLES = %w[primary backup].freeze

  belongs_to :user
  belongs_to :revoked_by, class_name: "User", optional: true
  has_many :wrapped_shares, class_name: "KeyCustodyWrappedShare", foreign_key: :hardware_key_id,
                            dependent: :delete_all, inverse_of: :hardware_key

  validates :external_id, presence: true, uniqueness: true
  validates :public_key, presence: true
  validates :role, inclusion: { in: ROLES }
  validates :nickname, length: { maximum: 60 }
  validates :revoked_reason, presence: true, if: :revoked_at?

  scope :active, -> { where(revoked_at: nil) }
  # Active keys that a share can be sealed to.
  scope :sealable, -> { active.where.not(seal_public_key: nil) }

  before_validation(on: :create) { self.seal_salt ||= Base64.urlsafe_encode64(SecureRandom.random_bytes(32), padding: false) }
  validates :seal_salt, presence: true

  def active? = revoked_at.nil?

  def label = [role.capitalize, nickname.presence].compact.join(": ")

  def sealable? = active? && seal_public_key.present?

  def seal_public_key_bytes = seal_public_key && Base64.strict_decode64(seal_public_key)

end
