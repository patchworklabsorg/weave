# frozen_string_literal: true

# The Knot: a one-way fingerprint of a verified person (proposal section 06,
# docs/KYC.md). "When you cut a thread, the knot stays tied."
#
# A Knot is a set of keyed hashes (KnotHash), never the identifiers behind
# them. It is keyed to the member (user_id) while the account is live. When
# the account is deleted, KnotLinker.write_record_and_detach! empties user_id
# and the Knot stays.
#
# The Knot carries exactly two pieces of state, and neither holds a reason, a
# history or a name:
# - blacklisted: yes or no. Only a two-key sign-off changes it (see
#   KnotChanges). The reason is in the verification audit record.
# - the program grants received (ProgramGrant). Re-verification reads them to
#   apply the per-program caps (see KnotGrants).
#
# There is no paper trail and there are no timestamps on purpose: a history of
# the flag would be a history.
# == Schema Information
#
# Table name: knots
# Database name: primary
#
#  id          :bigint           not null, primary key
#  blacklisted :boolean          default(FALSE), not null
#  user_id     :bigint
#
# Indexes
#
#  index_knots_on_user_id  (user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class Knot < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :knot

  belongs_to :user, optional: true
  has_many :knot_hashes, dependent: :delete_all
  has_many :program_grants, dependent: :delete_all
  has_many :change_requests, class_name: "KnotChangeRequest", dependent: :delete_all
  # Every passed attempt linked to this Knot, also from deleted accounts,
  # while the audit records are kept.
  has_many :verifications, dependent: :nullify

  scope :detached, -> { where(user_id: nil) }

  def detached? = user_id.nil?

  # Grants received from one program.
  def grants_received(program) = program_grants.where(program: program.to_s).count

  # The verification audit record that holds the reasons for changes to this
  # Knot: the newest decided attempt linked to it.
  def audit_verification
    verifications.where.not(decided_at: nil).order(:decided_at, :id).last
  end

end
