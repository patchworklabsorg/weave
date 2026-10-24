# frozen_string_literal: true

# Program grants on a member's Knot (see KnotGrants). KnotGrants checks who
# may act: the program's patch lead (or an owner) records a grant, and only the
# patch lead asks for an override over the cap.
class Admin::UserProgramGrantsController < Admin::BaseController
  before_action :set_user

  def create
    result = KnotGrants.record(@user, program: params[:program].to_s, by: current_user)
    respond(result, "Grant recorded on the member's Knot.")
  end

  def override
    result = KnotGrants.request_override(@user, program: params[:program].to_s, by: current_user, reason: params[:reason])
    respond(result, "Override requested. A board member must sign it off.")
  end

  private

  def set_user
    @user = User.find_by!(p_id: params[:user_id])
  end

  def respond(result, notice)
    if result.success?
      redirect_to admin_user_path(@user), notice:
    else
      redirect_to admin_user_path(@user),
                  alert: "Not saved: #{result.errors.map { |key, message| key == :base ? message : "#{key.to_s.humanize} #{message}" }.join('. ')}."
    end
  end

end
