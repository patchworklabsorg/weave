# frozen_string_literal: true

# GET /api/v1/directory/users/:sub
# GET /api/v1/directory/users?role=<key>  or  ?group=<slug>
# GET /api/v1/directory/users?patch=<slug>&patch_role=<key>  (key "lead" for
#   the patch leads). Only for an app whose scopes list `patches`, and only
#   for the patch the app belongs to (see PatchRoles).
#
# A user the calling app may not serve is reported as not found, the same as
# an unknown user, so the app can't learn who else has a Weave account.
module Api
  module V1
    module Directory
      class UsersController < BaseController
        def index
          users = filtered_users
          return if performed?

          users = users.select { |user| AppAccess.permitted?(user, current_application) }
          # The patches field reads each user's roles (see PatchRoles).
          if current_application.scopes.exists?("patches")
            ActiveRecord::Associations::Preloader.new(records: users, associations: :active_user_roles).call
          end
          render json: { users: users.sort_by(&:p_id).map { |user| serialize(user) } }
        end

        def show
          user = User.find_by(p_id: params[:sub])
          return render_not_found unless user && AppAccess.permitted?(user, current_application)

          render json: serialize(user)
        end

        private

        def filtered_users
          filters = [params[:role], params[:group], params[:patch]].count(&:present?)
          if filters != 1 || params[:patch].present? != params[:patch_role].present?
            render json: { error: "invalid_request", error_description: "Pass exactly one of role, group or patch (with patch_role)" },
                   status: :bad_request
          elsif params[:role].present?
            users_with_role
          elsif params[:group].present?
            users_in_group
          else
            users_with_patch_role
          end
        end

        def users_with_role
          role = ApplicationRole.for_application(current_application).find_by(key: params[:role])
          return render_not_found unless role

          assignments = role.assignments.to_a
          direct = User.where(id: assignments.select { |a| a.assignee_type == "User" }.map(&:assignee_id))
          via_group = User.where(id: Group::Membership.active.where(group_id: assignments.select { |a| a.assignee_type == "Group" }.map(&:assignee_id)).select(:user_id))
          direct.or(via_group).to_a
        end

        # Only a group linked to the calling app. Any other group is not found.
        def users_in_group
          group = AppAccess.linked_groups(current_application).find_by(slug: params[:group])
          return render_not_found unless group

          group.users.to_a
        end

        # The holders of one patch role, directly or through an active group
        # membership (PatchRole.held_by), or the patch leads for "lead".
        # Needs the patches scope on the app, like the claim. A patch other
        # than the app's own, and an unknown role key, are not found.
        def users_with_patch_role
          unless current_application.scopes.exists?("patches")
            return render json: { error: "insufficient_scope", error_description: "Use an app allowed the patches scope" },
                          status: :forbidden
          end

          patch = current_application.patch
          return render_not_found unless patch && patch.slug == params[:patch]

          patch_role_holders(patch, params[:patch_role].to_s)
        end

        def patch_role_holders(patch, key)
          if key == PatchRoles::LEAD
            return User.where(id: UserRole.active.for_role("patch_lead").where(scope: patch.slug).select(:user_id)).to_a
          end

          role = patch.roles.find_by(key:)
          return render_not_found unless role

          assignments = role.assignments.to_a
          direct = User.where(id: assignments.select { |a| a.assignee_type == "User" }.map(&:assignee_id))
          via_group = User.where(id: Group::Membership.active.where(group_id: assignments.select { |a| a.assignee_type == "Group" }.map(&:assignee_id)).select(:user_id))
          direct.or(via_group).to_a
        end

        def serialize(user) = DirectoryUserSerializer.new(user, current_application).as_json

      end
    end
  end
end
