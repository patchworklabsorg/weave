# frozen_string_literal: true

# The share of one key holder in one key set (see KeyCustody). Weave keeps
# only the x value and a digest of the share, so it can refuse a wrong share
# before it combines anything. The share itself is never stored: the holder's
# browser keeps it wrapped (KeyCustodyWrappedShare) and opens it with a
# hardware key.
# == Schema Information
#
# Table name: key_custody_shares
# Database name: primary
#
#  id         :bigint           not null, primary key
#  digest     :string           not null
#  x          :integer          not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  holder_id  :bigint
#  key_set_id :bigint           not null
#
# Indexes
#
#  index_key_custody_shares_on_holder_id                 (holder_id)
#  index_key_custody_shares_on_key_set_id                (key_set_id)
#  index_key_custody_shares_on_key_set_id_and_holder_id  (key_set_id,holder_id) UNIQUE
#  index_key_custody_shares_on_key_set_id_and_x          (key_set_id,x) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (holder_id => users.id) ON DELETE => nullify
#  fk_rails_...  (key_set_id => key_custody_key_sets.id)
#
class KeyCustodyShare < ApplicationRecord
  belongs_to :key_set, class_name: "KeyCustodyKeySet"
  belongs_to :holder, class_name: "User", optional: true
  has_many :wrapped_shares, class_name: "KeyCustodyWrappedShare", foreign_key: :share_id, dependent: :delete_all,
                            inverse_of: :share

  validates :x, numericality: { only_integer: true, in: 1..255 }
  validates :digest, format: { with: /\A\h{64}\z/ }

  def readonly? = persisted? || super

  # Does this share match the digest and x value on record?
  def matches?(share_bytes)
    return false unless share_bytes.is_a?(String) && share_bytes.bytesize == KeyCustody::Crypto::KEY_BYTES + 1
    return false unless share_bytes.getbyte(-1) == x

    OpenSSL.fixed_length_secure_compare(
      KeyCustody::Crypto.share_digest(share_bytes, public_key: key_set.public_key_bytes), digest
    )
  end

end
