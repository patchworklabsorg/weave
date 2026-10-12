# frozen_string_literal: true

# One impersonation of a user, with everything the admin did during it: the
# requests (Impersonation::Action) and the record changes (PaperTrail versions).
# Admin only, with the same view rule as the admin user page. The impersonated
# user never sees it.
class Admin::UserImpersonationsController < Admin::BaseController
  before_action :set_user
  before_action :ensure_can_view_user

  def show
    @impersonation = Impersonation.where(user: @user).includes(:admin).find(params[:id])
    @actions = @impersonation.actions.chronological
    @versions = @impersonation.versions.order(:created_at, :id)
  end

  private

  def set_user
    @user = User.find_by!(p_id: params[:user_id])
  end

  def ensure_can_view_user
    return if UserAdminPermissions.new(current_user, @user).view?

    redirect_to admin_users_path, alert: "You don't have permission to view this user"
  end

end
