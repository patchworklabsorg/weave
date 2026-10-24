# frozen_string_literal: true

# The append-only log of identity team governance (see IdentityGovernance).
# Each proposal, approval, rejection, expiry, removal,
# bootstrap step and board membership change adds one row. A row never changes and the app never deletes
# one. The governance page and the monthly board report read these rows.
# == Schema Information
#
# Table name: identity_governance_events
# Database name: primary
#
#  id                              :bigint           not null, primary key
#  data                            :jsonb            not null
#  kind                            :string           not null
#  created_at                      :datetime         not null
#  actor_id                        :bigint
#  identity_governance_proposal_id :bigint
#  subject_id                      :bigint
#
# Indexes
#
#  index_identity_governance_events_on_actor_id    (actor_id)
#  index_identity_governance_events_on_created_at  (created_at)
#  index_identity_governance_events_on_proposal    (identity_governance_proposal_id)
#  index_identity_governance_events_on_subject_id  (subject_id)
#
# Foreign Keys
#
#  fk_rails_...  (actor_id => users.id) ON DELETE => nullify
#  fk_rails_...  (identity_governance_proposal_id => identity_governance_proposals.id) ON DELETE => nullify
#  fk_rails_...  (subject_id => users.id) ON DELETE => nullify
#
class IdentityGovernanceEvent < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :igev

  KINDS = %w[
    proposed approved rejected withdrawn expired cancelled applied
    member_removed bootstrap_member_added
    board_member_added board_member_removed
  ].freeze

  class ImmutableError < StandardError; end

  belongs_to :actor, class_name: "User", optional: true
  belongs_to :subject, class_name: "User", optional: true
  belongs_to :identity_governance_proposal, optional: true

  validates :kind, inclusion: { in: KINDS }

  before_update { raise ImmutableError, "Governance events can't change" }
  before_destroy { raise ImmutableError, "Governance events can't be deleted" }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def self.record!(kind, actor:, subject: nil, proposal: nil, **data)
    create!(kind: kind.to_s, actor:, subject:, identity_governance_proposal: proposal, data:)
  end

  def readonly? = persisted? || super

  def proposal = identity_governance_proposal

  # One line for the governance page and the board report.
  def summary
    who = actor&.full_name || (actor_id ? "A deleted user" : "Weave")
    about = subject&.full_name || "a deleted user"
    case kind
    when "proposed" then "#{who} proposed: #{IdentityGovernanceProposal.describe(data['proposal_kind'], about, data['proposal_scope'])}."
    when "approved" then "#{who} approved: #{IdentityGovernanceProposal.describe(data['proposal_kind'], about, data['proposal_scope'])}."
    when "rejected" then "#{who} rejected: #{IdentityGovernanceProposal.describe(data['proposal_kind'], about, data['proposal_scope'])}."
    when "withdrawn" then "#{who} withdrew: #{IdentityGovernanceProposal.describe(data['proposal_kind'], about, data['proposal_scope'])}."
    when "expired" then "Expired: #{IdentityGovernanceProposal.describe(data['proposal_kind'], about, data['proposal_scope'])}."
    when "cancelled" then "Cancelled: #{IdentityGovernanceProposal.describe(data['proposal_kind'], about, data['proposal_scope'])}."
    when "applied" then "Applied: #{IdentityGovernanceProposal.describe(data['proposal_kind'], about, data['proposal_scope'])}."
    when "member_removed" then "#{who} removed #{about} from the identity team."
    when "bootstrap_member_added" then "#{who} added #{about} to the identity team in the bootstrap."
    when "board_member_added" then "#{who} added #{about} to the board."
    when "board_member_removed" then "#{who} removed #{about} from the board."
    else kind.humanize
    end
  end

end
