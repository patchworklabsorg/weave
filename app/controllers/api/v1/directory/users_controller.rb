# frozen_string_literal: true

# GET /api/v1/directory/users/:sub
# GET /api/v1/directory/users?role=<key>  or  ?group=<slug>
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
          render json: { users: users.sort_by(&:p_id).map { |user| serialize(user) } }
        end

        def show
          user = User.find_by(p_id: params[:sub])
          return render_not_found unless user && AppAccess.permitted?(user, current_application)

          render json: serialize(user)
        end

        private

        def filtered_users
          if params[:role].present? == params[:group].present?
            render json: { error: "invalid_request", error_description: "Pass exactly one of role or group" }, status: :bad_request
          elsif params[:role].present?
            users_with_role
          else
            users_in_group
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

        def serialize(user) = DirectoryUserSerializer.new(user, current_application).as_json

      end
    end
  end
end
