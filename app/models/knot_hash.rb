# frozen_string_literal: true

# One keyed hash of a Knot (see KnotHasher). digest is a hex HMAC-SHA256. No
# identifier is stored in plain text. A strong digest (document, national_id)
# belongs to one Knot only. The soft digest can be on many Knots.
# == Schema Information
#
# Table name: knot_hashes
# Database name: primary
#
#  id      :bigint           not null, primary key
#  digest  :string           not null
#  kind    :string           not null
#  knot_id :bigint           not null
#
# Indexes
#
#  index_knot_hashes_on_kind_and_digest              (kind,digest)
#  index_knot_hashes_on_knot_id_and_kind_and_digest  (knot_id,kind,digest) UNIQUE
#  index_knot_hashes_on_strong_digest                (kind,digest) UNIQUE WHERE ((kind)::text <> 'soft'::text)
#
# Foreign Keys
#
#  fk_rails_...  (knot_id => knots.id)
#
class KnotHash < ApplicationRecord
  belongs_to :knot

  validates :kind, inclusion: { in: KnotHasher::KINDS }
  validates :digest, format: { with: /\A\h{64}\z/ }

  scope :strong, -> { where(kind: KnotHasher::STRONG_KINDS) }
  scope :soft, -> { where(kind: "soft") }

  # Rows that match any of the digests (KnotHasher::Digest).
  def self.matching(digests)
    return none if digests.empty?

    digests.map { |found| where(kind: found.kind, digest: found.digest) }.reduce(:or)
  end

  def strong? = KnotHasher::STRONG_KINDS.include?(kind)

end
