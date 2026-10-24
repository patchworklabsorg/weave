# frozen_string_literal: true

# Proposals to change the identity team: propose, approve, reject, withdraw
# (see IdentityGovernance).
class Identity::GovernanceProposalsController < Identity::BaseController
  include IdentityGovernanceAccess

  before_action :set_proposal, except: :create

  def show
    @preconditions = IdentityGovernance.preconditions(@proposal.subject) if @proposal.subject && @proposal.kind == "add_member"
    @events = @proposal.events.includes(:actor).order(:created_at, :id)
    @board = User.where(is_board: true).order(:first_name)
  end

  def create
    result = IdentityGovernance.propose(kind: params[:kind], subject: find_person(params[:person]), by: current_user,
                                        reason: params[:reason])
    if result.success?
      redirect_to identity_governance_proposal_path(result.record), notice: "Proposed. The board members who can approve got an email."
    else
      redirect_to identity_governance_path, alert: "Not proposed: #{result.message}."
    end
  end

  def approve
    result = IdentityGovernance.approve(@proposal, by: current_user)
    if result.success?
      notice = @proposal.reload.applied? ? "Approved. The change is applied." : "Approved. More board members must approve."
      redirect_to identity_governance_proposal_path(@proposal), notice:
    else
      redirect_to identity_governance_proposal_path(@proposal), alert: "Not approved: #{result.message}"
    end
  end

  def reject
    result = IdentityGovernance.reject(@proposal, by: current_user, reason: params[:reason])
    if result.success?
      redirect_to identity_governance_proposal_path(@proposal), notice: "Rejected."
    else
      redirect_to identity_governance_proposal_path(@proposal), alert: "Not rejected: #{result.message}."
    end
  end

  def withdraw
    result = IdentityGovernance.withdraw(@proposal, by: current_user)
    if result.success?
      redirect_to identity_governance_path, notice: "Withdrawn."
    else
      redirect_to identity_governance_proposal_path(@proposal), alert: "Not withdrawn: #{result.message}"
    end
  end

  private

  def set_proposal
    @proposal = IdentityGovernanceProposal.find_by_public_param!(params[:id])
  end

end
