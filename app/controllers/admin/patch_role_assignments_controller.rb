# frozen_string_literal: true

# Gives a role of a patch to a user or a group, or takes it away (see
# PatchRoleAssignment). Only a superadmin gives a role, like the roles
# themselves. Any admin takes one away, so access is quick to remove.
class Admin::PatchRoleAssignmentsController < Admin::BaseController
  before_action :set_role
  before_action :require_superadmin, only: [:create]

  def create
    assignee = find_assignee
    return redirect_back_to_roles(alert: assignee_not_found_message) unless assignee

    assignment = @role.assignments.new(assignee: assignee, created_by: current_user)

    if assignment.save
      redirect_back_to_roles(notice: "#{assignee_label(assignee)} has the #{@role.name} role now.")
    else
      redirect_back_to_roles(alert: assignment.errors.full_messages.to_sentence)
    end
  end

  def destroy
    assignment = @role.assignments.find_by_public_param!(params[:id])
    assignment.destroy!
    redirect_back_to_roles(notice: "#{assignee_label(assignment.assignee)} no longer has the #{@role.name} role.")
  end

  private

  def set_role
    @patch = Patch.find_by!(slug: params[:patch_id])
    @role = @patch.roles.find_by_public_param!(params[:role_id])
  end

  def require_superadmin
    return if current_user.superadmin?

    redirect_to admin_patch_path(@patch), alert: "Only a superadmin can change the roles of a patch."
  end

  def assignment_params
    params.require(:assignment).permit(:group_id, :email)
  end

  def find_assignee
    if assignment_params[:group_id].present?
      Group.find_by_public_id(assignment_params[:group_id].to_s)
    elsif assignment_params[:email].present?
      User.find_for_any_email(assignment_params[:email])
    end
  end

  def assignee_not_found_message
    assignment_params[:group_id].present? ? "That group doesn't exist." : "No user has that email address."
  end

  def assignee_label(assignee)
    assignee.is_a?(Group) ? "The #{assignee.name} group" : assignee.full_name
  end

  def redirect_back_to_roles(**flash)
    redirect_to admin_patch_path(@patch, anchor: "roles"), **flash
  end

end
