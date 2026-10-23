# frozen_string_literal: true

# Removes a member from the identity team at once (see
# IdentityGovernance.remove_member). Any one owner or identity team lead can
# do it, with a reason. The board gets an email.
class Identity::TeamRemovalsController < Identity::BaseController
  include IdentityGovernanceAccess

  def create
    subject = User.find_by(p_id: params[:user_id].to_s)
    result = IdentityGovernance.remove_member(subject, by: current_user, reason: params[:reason])
    if result.success?
      redirect_to identity_governance_path, notice: "Removed #{subject.full_name} from the identity team. The board was told."
    else
      redirect_to identity_governance_path, alert: "Not removed: #{result.message}."
    end
  end

end
