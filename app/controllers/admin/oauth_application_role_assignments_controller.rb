# frozen_string_literal: true

# Gives a role in an OAuth app to a user or a group, or takes it away.
# Superadmin only: a role is sent to the app and gives access to it.
class Admin::OauthApplicationRoleAssignmentsController < Admin::BaseController
  before_action :set_role
  before_action :require_superadmin

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
    assignment = @role.assignments.find(params[:id])
    assignment.destroy!
    redirect_back_to_roles(notice: "#{assignee_label(assignment.assignee)} no longer has the #{@role.name} role.")
  end

  private

  def set_role
    @application = Doorkeeper::Application.find(params[:oauth_application_id])
    @role = ApplicationRole.for_application(@application).find(params[:role_id])
  end

  def require_superadmin
    return if current_user.superadmin?

    redirect_to admin_oauth_application_path(@application), alert: "Only a superadmin can change the roles of an app."
  end

  def assignment_params
    params.require(:assignment).permit(:group_id, :email)
  end

  def find_assignee
    if assignment_params[:group_id].present?
      Group.find_by(id: assignment_params[:group_id])
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
    redirect_to admin_oauth_application_path(@application, anchor: "roles"), **flash
  end

end
