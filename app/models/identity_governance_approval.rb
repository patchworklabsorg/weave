# frozen_string_literal: true

# One approval of an IdentityGovernanceProposal. A row never changes.
# == Schema Information
#
# Table name: identity_governance_approvals
# Database name: primary
#
#  id                              :bigint           not null, primary key
#  created_at                      :datetime         not null
#  approver_id                     :bigint
#  identity_governance_proposal_id :bigint           not null
#
# Indexes
#
#  index_identity_governance_approvals_on_approver_id            (approver_id)
#  index_identity_governance_approvals_on_proposal               (identity_governance_proposal_id)
#  index_identity_governance_approvals_on_proposal_and_approver  (identity_governance_proposal_id,approver_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (approver_id => users.id) ON DELETE => nullify
#  fk_rails_...  (identity_governance_proposal_id => identity_governance_proposals.id)
#
class IdentityGovernanceApproval < ApplicationRecord
  belongs_to :identity_governance_proposal
  belongs_to :approver, class_name: "User", optional: true

  validates :approver_id, uniqueness: { scope: :identity_governance_proposal_id }, on: :create

  def readonly? = persisted? || super

end
