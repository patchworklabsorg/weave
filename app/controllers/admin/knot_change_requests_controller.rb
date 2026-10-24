# frozen_string_literal: true

# The second key of a two-key change to a Knot (see KnotChanges). KnotChanges
# checks who may sign off: never the requester or the member, a board member
# for a grant override, else an identity team member.
class Admin::KnotChangeRequestsController < Admin::BaseController
  before_action :set_request

  def sign_off
    result = KnotChanges.sign_off(@request, by: current_user)
    if result.success?
      redirect_to admin_knots_path, notice: "Signed off. The change is applied."
    else
      redirect_to admin_knots_path, alert: "Not signed off: #{result.errors.values.join('. ')}."
    end
  end

  def decline
    result = KnotChanges.decline(@request, by: current_user, reason: params[:reason])
    if result.success?
      redirect_to admin_knots_path, notice: "Declined. Nothing changed."
    else
      redirect_to admin_knots_path, alert: "Not declined: #{result.errors.map { |key, message| key == :base ? message : "#{key.to_s.humanize} #{message}" }.join('. ')}."
    end
  end

  private

  def set_request
    @request = KnotChangeRequest.find_by_public_param!(params[:id])
  end

end
