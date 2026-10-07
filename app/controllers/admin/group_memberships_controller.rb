# frozen_string_literal: true

# Adds and removes members of a manual group. Superadmin only, for the reason
# given in Admin::GroupsController.
class Admin::GroupMembershipsController < Admin::BaseController
  before_action :require_superadmin
  before_action :set_group
  before_action :require_editable_group

  def create
    user = User.find_for_any_email(membership_params[:email])
    return redirect_to(admin_group_path(@group), alert: "No user has that email address.") unless user

    membership = @group.memberships.build(
      user: user,
      added_by: current_user,
      source: "manual",
      expires_at: membership_params[:expires_at].presence
    )

    if membership.save
      redirect_to admin_group_path(@group), notice: "#{user.full_name} was added to #{@group.name}."
    else
      redirect_to admin_group_path(@group), alert: membership.errors.full_messages.to_sentence
    end
  end

  def destroy
    membership = @group.memberships.find(params[:id])
    membership.destroy!
    redirect_to admin_group_path(@group), notice: "#{membership.user.full_name} was removed from #{@group.name}."
  end

  private

  def set_group
    @group = Group.find_by!(slug: params[:group_id])
  end

  def membership_params
    params.require(:group_membership).permit(:email, :expires_at)
  end

  def require_superadmin
    return if current_user.superadmin?

    redirect_to admin_groups_path, alert: "Only a superadmin can change groups."
  end

  def require_editable_group
    return if @group.editable?

    redirect_to admin_group_path(@group), alert: "System groups follow user attributes and can't be changed by hand."
  end

end
