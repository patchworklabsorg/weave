# frozen_string_literal: true

# A change to the identity team that waits for approval (see
# IdentityGovernance).
#
# | Kind              | Proposer | Approval                                      |
# | ----------------- | -------- | --------------------------------------------- |
# | add_member        | owner    | one board member, not the proposer or subject |
# | set_lead          | owner    | one board member, not the proposer or subject |
# | clear_lead        | owner    | one board member, not the proposer or subject |
# | add_key_holder    | owner    | every board member at proposal time           |
# | remove_key_holder | owner    | every board member at proposal time           |
#
# Removal from the team needs no proposal (see IdentityGovernance.remove_member).
# == Schema Information
#
# Table name: identity_governance_proposals
# Database name: primary
#
#  id                    :bigint           not null, primary key
#  close_reason          :text
#  closed_at             :datetime
#  expires_at            :datetime         not null
#  kind                  :string           not null
#  reason                :text             not null
#  required_approver_ids :bigint           default([]), not null, is an Array
#  scope                 :string
#  status                :string           default("pending"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  closed_by_id          :bigint
#  proposed_by_id        :bigint
#  subject_id            :bigint
#
# Indexes
#
#  index_identity_governance_proposals_on_closed_by_id           (closed_by_id)
#  index_identity_governance_proposals_on_proposed_by_id         (proposed_by_id)
#  index_identity_governance_proposals_on_status_and_expires_at  (status,expires_at)
#  index_identity_governance_proposals_on_subject_id             (subject_id)
#
# Foreign Keys
#
#  fk_rails_...  (closed_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (proposed_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (subject_id => users.id) ON DELETE => nullify
#
class IdentityGovernanceProposal < ApplicationRecord
  include EncodedIds::HashidIdentifiable
  set_public_id_prefix :igpr

  has_paper_trail

  KINDS = %w[add_member set_lead clear_lead add_key_holder remove_key_holder add_patch_lead].freeze
  KEY_HOLDER_KINDS = %w[add_key_holder remove_key_holder].freeze
  STATUSES = %w[pending applied rejected withdrawn expired cancelled].freeze

  belongs_to :subject, class_name: "User", optional: true
  belongs_to :proposed_by, class_name: "User", optional: true
  belongs_to :closed_by, class_name: "User", optional: true
  has_many :approvals, class_name: "IdentityGovernanceApproval", dependent: :destroy
  has_many :approvers, through: :approvals
  has_many :events, class_name: "IdentityGovernanceEvent", dependent: nil

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :reason, presence: true
  validates :expires_at, presence: true

  scope :pending, -> { where(status: "pending") }
  scope :awaiting_approval, -> { pending.where(expires_at: Time.current..) }
  scope :due_to_expire, -> { pending.where(expires_at: ...Time.current) }

  STATUSES.each do |name|
    define_method(:"#{name}?") { status == name }
  end

  def self.describe(kind, name, scope = nil)
    case kind.to_s
    when "add_member" then "add #{name} to the identity team"
    when "set_lead" then "make #{name} an identity team lead"
    when "clear_lead" then "remove #{name} as an identity team lead"
    when "add_key_holder" then "make #{name} a key holder"
    when "remove_key_holder" then "remove #{name} as a key holder"
    when "add_patch_lead" then "make #{name} the patch lead of #{scope ? KnotSettings.program(scope)&.name || scope : 'a program'}"
    else kind.to_s.humanize
    end
  end

  def description = self.class.describe(kind, subject&.full_name || "a deleted user", scope)

  def key_holder_change? = KEY_HOLDER_KINDS.include?(kind)

  # The role of this proposal (see IdentityGovernance::KIND_ROLES).
  def role_key = IdentityGovernance.kind_role(kind).first

  # Every board member at proposal time must approve (the
  # owner_proposes_all_board_approve rule in config/roles.yml).
  def all_board? = IdentityGovernance.kind_rule(kind).all_board?

  def open? = pending? && expires_at.future?

  def expired_now? = pending? && !expires_at.future?

  def approver_ids = approvals.pluck(:approver_id)

  # For a key holder change: the board members who still must approve.
  def missing_approver_ids = required_approver_ids - approver_ids

end
