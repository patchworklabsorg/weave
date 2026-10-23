# frozen_string_literal: true

# The identity team governance page (see IdentityGovernance): the team, the
# proposals that wait, the forms to propose or remove a member, the roles with their holders and grant rules, the log, and the
# permanent log of privileged attributes.
class Identity::GovernanceController < Identity::BaseController
  include IdentityGovernanceAccess

  LOG_LIMIT = 50

  def show
    @team = User.identity_team.with_roles.order(:first_name, :last_name)
    @role_assignments = RoleRegistry.keys.index_with { |key| RoleGrants.assignments(key).to_a }
    @pending = IdentityGovernanceProposal.pending.includes(:subject, :proposed_by, :approvers).order(:expires_at)
    @recent = IdentityGovernanceProposal.where.not(status: "pending").includes(:subject, :proposed_by)
                                        .order(updated_at: :desc).limit(20)
    @events = IdentityGovernanceEvent.newest_first.includes(:actor, :subject).limit(LOG_LIMIT)
    @bootstrap_open = IdentityGovernance.bootstrap_open?
    @privileged_changes = PrivilegedAttributeChange.newest_first.includes(:actor).limit(LOG_LIMIT)
  end

end
