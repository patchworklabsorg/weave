# frozen_string_literal: true

# The identity team governance page (see IdentityGovernance): the team, the
# proposals that wait, the forms to propose, record an NDA or remove a
# member, the log, and the permanent log of privileged attributes.
class Identity::GovernanceController < Identity::BaseController
  include IdentityGovernanceAccess

  LOG_LIMIT = 50

  def show
    @team = User.identity_team.order(:first_name, :last_name)
    @pending = IdentityGovernanceProposal.pending.includes(:subject, :proposed_by, :approvers).order(:expires_at)
    @recent = IdentityGovernanceProposal.where.not(status: "pending").includes(:subject, :proposed_by)
                                        .order(updated_at: :desc).limit(20)
    @events = IdentityGovernanceEvent.newest_first.includes(:actor, :subject).limit(LOG_LIMIT)
    @ndas = IdentityNda.newest_first.includes(:user, :recorded_by).limit(LOG_LIMIT)
    @bootstrap_open = IdentityGovernance.bootstrap_open?
    @privileged_changes = PrivilegedAttributeChange.newest_first.includes(:actor).limit(LOG_LIMIT)
  end

end
