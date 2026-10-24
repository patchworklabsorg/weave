# frozen_string_literal: true

# The append-only audit record of a verification (see Verification). Each step
# of the flow, each view of the ID image and each break-glass action adds one
# row. A row never changes and the app never deletes one: if an outcome is
# disputed later, we read these rows again.
#
# data holds the facts of the step, for example who attended the call, the
# document type, the outcome and the written reason. It never holds a value
# from the ID (see VerificationIdentifiers).
# == Schema Information
#
# Table name: verification_events
# Database name: primary
#
#  id              :bigint           not null, primary key
#  data            :jsonb            not null
#  kind            :string           not null
#  created_at      :datetime         not null
#  actor_id        :bigint
#  user_id         :bigint
#  verification_id :bigint           not null
#
# Indexes
#
#  index_verification_events_on_actor_id         (actor_id)
#  index_verification_events_on_kind             (kind)
#  index_verification_events_on_user_id          (user_id)
#  index_verification_events_on_verification_id  (verification_id)
#
# Foreign Keys
#
#  fk_rails_...  (actor_id => users.id) ON DELETE => nullify
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#  fk_rails_...  (verification_id => verifications.id)
#
class VerificationEvent < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :vevt

  KINDS = %w[
    submitted pre_review_started pre_review_taken_over document_viewed document_rejected document_approved call_scheduled decided
    escalated escalation_resolved document_purged document_sealed
    break_glass_requested break_glass_approved break_glass_approval_lapsed break_glass_granted break_glass_denied
    document_decrypted break_glass_grant_wiped break_glass_handoff_expired
    member_notice_delayed member_notice_delay_signed_off member_notice_delay_lifted
    member_notice_delay_expired reverification_required
    knot_review_required knot_duplicate_account knot_linked
    knot_change_requested knot_change_signed_off knot_change_declined program_grant_recorded
    residency_recorded
  ].freeze

  class ImmutableError < StandardError; end

  belongs_to :verification
  belongs_to :user, optional: true
  belongs_to :actor, class_name: "User", optional: true

  validates :kind, inclusion: { in: KINDS }

  before_update { raise ImmutableError, "Verification events can't change" }
  before_destroy { raise ImmutableError, "Verification events can't be deleted" }

  def self.record!(verification, kind, actor: nil, **data)
    create!(verification:, user_id: verification.user_id, actor:, kind: kind.to_s, data:)
  end

  def readonly? = persisted? || super

end
