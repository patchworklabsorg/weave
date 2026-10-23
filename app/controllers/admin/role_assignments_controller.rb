# frozen_string_literal: true

# Grants and revokes the roles with an immediate rule (see RoleGrants and
# config/roles.yml): staff and contractor (any admin), board member and the
# removal of a patch lead (one owner). The index lists the staff and the
# contractors, with a form to grant either role by Weave ID or email.
#
# A role with a proposal rule (verifier, identity lead, key holder, a new
# patch lead) goes through the identity governance page. RoleGrants refuses
# it here.
class Admin::RoleAssignmentsController < Admin::BaseController
  PAGE_ROLES = %w[staff contractor].freeze

  before_action :require_known_role, only: [:create, :revoke]

  def index
    @assignments = PAGE_ROLES.index_with { |key| RoleGrants.assignments(key).includes(:granted_by).to_a }
  end

  def create
    user = find_person
    result = RoleGrants.grant(user, params[:role].to_s, by: current_user, reason: params[:reason], scope: params[:scope])
    finish(result, user, "Granted.", "Not granted")
  end

  def revoke
    user = find_person
    result = RoleGrants.revoke(user, params[:role].to_s, by: current_user, reason: params[:reason], scope: params[:scope])
    finish(result, user, "Revoked.", "Not revoked")
  end

  private

  def require_known_role
    return if RoleRegistry.known?(params[:role])

    redirect_to admin_role_assignments_path, alert: "Unknown role."
  end

  def find_person
    value = (params[:user_id].presence || params[:person]).to_s.strip
    return nil if value.blank?

    User.find_by(p_id: value) || User.find_by(email: value.downcase)
  end

  def finish(result, user, notice, failure)
    target = params[:return_to] == "user" && user ? admin_user_path(user, anchor: "roles") : admin_role_assignments_path
    if result.success?
      redirect_to target, notice:
    else
      redirect_to target, alert: "#{failure}: #{result.message}"
    end
  end

end
