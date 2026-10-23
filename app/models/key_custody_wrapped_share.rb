# frozen_string_literal: true

# A key holder's share, sealed to the seal public key of one of their
# hardware keys (X25519, HKDF-SHA256, AES-256-GCM; see KeyCustody::Crypto).
# The ceremony page seals it, or the holder's own browser at a rewrap. Only
# the PRF output of that hardware key, in the holder's browser, gives the seal
# private key, so Weave can't open this value. Each holder has one for each
# of their hardware keys.
# == Schema Information
# Schema version: 20261023120000
#
# Table name: key_custody_wrapped_shares
# Database name: primary
#
#  id              :bigint           not null, primary key
#  sealed          :text             not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  hardware_key_id :bigint           not null
#  share_id        :bigint           not null
#
# Indexes
#
#  idx_on_share_id_hardware_key_id_f328b38774           (share_id,hardware_key_id) UNIQUE
#  index_key_custody_wrapped_shares_on_hardware_key_id  (hardware_key_id)
#  index_key_custody_wrapped_shares_on_share_id         (share_id)
#
# Foreign Keys
#
#  fk_rails_...  (hardware_key_id => identity_hardware_keys.id) ON DELETE => cascade
#  fk_rails_...  (share_id => key_custody_shares.id) ON DELETE => cascade
#
class KeyCustodyWrappedShare < ApplicationRecord
  belongs_to :share, class_name: "KeyCustodyShare"
  belongs_to :hardware_key, class_name: "IdentityHardwareKey"

  validates :sealed, presence: true
  validates :hardware_key_id, uniqueness: { scope: :share_id }

  def readonly? = persisted? || super

  # The additional data bound to the seal. It ties the sealed share to its
  # key set, holder, hardware key and x value.
  def self.aad(key_set:, holder:, hardware_key_external_id:, x:)
    "weave key custody sealed share v1|#{key_set.public_key}|#{holder.public_id}|#{hardware_key_external_id}|#{x}"
  end

  def aad = self.class.aad(key_set: share.key_set, holder: share.holder, hardware_key_external_id: hardware_key.external_id, x: share.x)

  def sealed_bytes = Base64.urlsafe_decode64(sealed)

  # What the browser needs to open it.
  def blob = { sealed:, aad: }

end
