# frozen_string_literal: true

# A group manager adds and removes members of their group (see GroupPolicy
# and Group::MembershipPolicy). Adding a member is a grant of access, so an
# admin who impersonates a manager can't do it for them.
class GroupMembersController < ApplicationController
  before_action :set_group
  before_action :refuse_while_impersonating
  after_action :verify_authorized

  def create
    authorize @group, :add_member?

    user = User.find_for_any_email(params.dig(:group_membership, :email))
    return redirect_to(group_path(@group), alert: "No user has that email address.") unless user

    membership = @group.memberships.build(user:, added_by: current_user, source: "manual", role: "member")
    if membership.save
      redirect_to group_path(@group), notice: "#{user.full_name} was added to #{@group.name}."
    else
      redirect_to group_path(@group), alert: membership.errors.full_messages.to_sentence
    end
  end

  def destroy
    membership = @group.memberships.find_by_public_param!(params[:id])
    authorize membership

    membership.destroy!
    redirect_to group_path(@group), notice: "#{membership.user.full_name} was removed from #{@group.name}."
  end

  private

  def set_group
    @group = Group.find_by!(slug: params[:group_id])
  end

  def refuse_while_impersonating
    return unless impersonating?

    redirect_to group_path(@group), alert: "You can't change group members while impersonating a user."
  end

end
