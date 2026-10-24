# frozen_string_literal: true

# Email for identity team governance (see IdentityGovernance): a proposal
# that waits for a board member, the notice to the board when a member is
# removed from the identity team, and the notice of a board change.
class IdentityGovernanceMailer < ApplicationMailer
  def approval_needed(proposal, approver)
    @proposal = proposal
    @url = identity_governance_proposal_url(proposal)

    mail(to: approver.email, subject: env_subject("[IDP Alert] Identity team change needs your approval (#{proposal.public_id})"))
  end

  def member_removed(event, board_member)
    @event = event
    @url = identity_governance_url

    mail(to: board_member.email, subject: env_subject("[IDP Alert] A member was removed from the identity team"))
  end

  # A change of board membership. The board approves identity team changes,
  # so every board member before and after the change is told.
  def board_changed(event, recipient)
    @event = event
    @url = identity_governance_url

    mail(to: recipient.email, subject: env_subject("[IDP Alert] The board membership changed"))
  end

end
