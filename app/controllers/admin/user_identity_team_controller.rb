# frozen_string_literal: true

# Sets a user's place on the identity team: member, key holder, lead (see
# User#identity_team). Only an owner can do it, and not for their own
# account, because key holders can open stored ID images.
class Admin::UserIdentityTeamController < Admin::BaseController
  before_action :require_owner

  def update
    user = User.find_by!(p_id: params[:user_id])
    if user == current_user
      redirect_to admin_user_path(user), alert: "Another owner must change your own place on the identity team."
      return
    end

    cast = ActiveModel::Type::Boolean.new
    team = cast.cast(params[:identity_team]) || false
    attributes = {
      identity_team: team,
      identity_key_holder: team && (cast.cast(params[:identity_key_holder]) || false),
      identity_lead: team && (cast.cast(params[:identity_lead]) || false)
    }
    if user.update(attributes)
      redirect_to admin_user_path(user), notice: "Updated the identity team role of #{user.full_name}."
    else
      redirect_to admin_user_path(user), alert: "Not updated: #{user.errors.full_messages.to_sentence}."
    end
  end

  private

  def require_owner
    return if current_user.owner?

    redirect_to admin_root_path, alert: "Only an owner can change the identity team."
  end

end
