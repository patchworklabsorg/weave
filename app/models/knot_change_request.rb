# frozen_string_literal: true

# A change to a Knot that waits for a second person's sign-off (see
# KnotChanges):
# - set_blacklist / clear_blacklist: two identity team members.
# - name_change: an identity team member checks continuity, a second one
#   signs off. digests holds the new one-way hashes (never the name).
# - grant_override: the program's patch lead asks, a board member signs off.
#
# The row is deleted when the change is signed off or declined, so the Knot
# keeps no history. The written reason and each step are in the verification
# audit record (VerificationEvent on verification).
# == Schema Information
#
# Table name: knot_change_requests
# Database name: primary
#
#  id              :bigint           not null, primary key
#  digests         :jsonb            not null
#  kind            :string           not null
#  program         :string
#  created_at      :datetime         not null
#  knot_id         :bigint           not null
#  requested_by_id :bigint
#  verification_id :bigint           not null
#
# Indexes
#
#  index_knot_change_requests_on_knot_id          (knot_id)
#  index_knot_change_requests_on_requested_by_id  (requested_by_id)
#  index_knot_change_requests_on_verification_id  (verification_id)
#
# Foreign Keys
#
#  fk_rails_...  (knot_id => knots.id)
#  fk_rails_...  (requested_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (verification_id => verifications.id) ON DELETE => cascade
#
class KnotChangeRequest < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :kreq

  KINDS = %w[set_blacklist clear_blacklist name_change grant_override].freeze

  belongs_to :knot
  belongs_to :verification
  belongs_to :requested_by, class_name: "User", optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :program, inclusion: { in: ->(_) { KnotSettings.program_keys } }, if: -> { kind == "grant_override" }
  validates :kind, uniqueness: { scope: %i[knot_id program], message: "has a request that waits for sign-off" }

  def blacklist_change? = kind.in?(%w[set_blacklist clear_blacklist])

  # The new hashes of a name change.
  def new_digests = digests.map { |row| KnotHasher::Digest.new(kind: row.fetch("kind"), digest: row.fetch("digest")) }

end
