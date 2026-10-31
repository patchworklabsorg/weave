# frozen_string_literal: true

# Staging only: an owner sets a member's identity verification, US residency
# or guardian consent to a test state (see StagingTestStates). Answers 404
# everywhere else, so production has no such page.
class Admin::StagingTestStatesController < Admin::BaseController
  before_action :require_staging_owner

  def update
    user = User.find_by!(p_id: params[:user_id])
    StagingTestStates.set!(user, area: params[:area], state: params[:state], by: current_user, us_state: params[:us_state])
    label = StagingTestStates::STATES.dig(params[:area], params[:state])
    redirect_to admin_user_path(user), notice: "The test state is set: #{label}."
  rescue StagingTestStates::Error => e
    redirect_to admin_user_path(user), alert: e.message
  end

  private

  def require_staging_owner
    raise ActionController::RoutingError, "Not Found" unless StagingTestStates.allowed?(current_user)
  end

end
