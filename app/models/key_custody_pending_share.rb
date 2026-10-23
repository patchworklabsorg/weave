# frozen_string_literal: true

# One share that waits for the next share of the same break-glass request or
# key set activation (see KeyCustody::PendingShares). Only PendingShares uses
# this model.
#
# - The share is encrypted with Lockbox. The plaintext starts with a digest of
#   memory_key, so a row copied to another request does not open.
# - One share alone reveals nothing about the master key (Shamir).
# - The row is deleted when the shares are combined, on a deny, and after
#   pending_share_minutes (SweepPendingSharesJob).
# - No PaperTrail, and the share never reaches a log (filter_attributes). It
#   is not member data, so it is not in the data-category matrix.
# == Schema Information
#
# Table name: key_custody_pending_shares
# Database name: primary
#
#  id               :bigint           not null, primary key
#  expires_at       :datetime         not null
#  memory_key       :string           not null
#  share_ciphertext :text             not null
#  created_at       :datetime         not null
#  holder_id        :bigint           not null
#
# Indexes
#
#  index_key_custody_pending_shares_on_expires_at                (expires_at)
#  index_key_custody_pending_shares_on_holder_id                 (holder_id)
#  index_key_custody_pending_shares_on_memory_key_and_holder_id  (memory_key,holder_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (holder_id => users.id) ON DELETE => cascade
#
class KeyCustodyPendingShare < ApplicationRecord
  self.filter_attributes += %i[share share_ciphertext]

  has_encrypted :share, type: :binary

  belongs_to :holder, class_name: "User"

  scope :live, -> { where(expires_at: Time.current..) }
  scope :expired, -> { where(expires_at: ...Time.current) }

  # The share, after a check that the row belongs to its memory_key.
  def share_bytes
    plain = share.to_s.b
    tag = self.class.tag(memory_key)
    raise KeyCustody::Refused, "A waiting share does not belong to this request." unless plain.start_with?(tag)

    plain.byteslice(tag.bytesize..)
  ensure
    KeyCustody::Crypto.wipe(plain) if plain
  end

  def self.bound(memory_key, share) = tag(memory_key) + share.b

  def self.tag(memory_key) = OpenSSL::Digest::SHA256.digest("weave pending share v1:#{memory_key}")

end
