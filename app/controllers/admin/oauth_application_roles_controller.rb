# frozen_string_literal: true

# Adds a role to an OAuth app, or deletes one (see ApplicationRole).
# Superadmin only: a role is sent to the app and gives access to it.
class Admin::OauthApplicationRolesController < Admin::BaseController
  before_action :set_application
  before_action :require_superadmin

  def create
    role = ApplicationRole.new(role_params.merge(application: @application, created_by: current_user))

    if role.save
      redirect_to admin_oauth_application_path(@application, anchor: "roles"), notice: "The #{role.name} role was added."
    else
      redirect_to admin_oauth_application_path(@application, anchor: "roles"), alert: role.errors.full_messages.to_sentence
    end
  end

  def destroy
    role = ApplicationRole.for_application(@application).find(params[:id])
    role.destroy!
    redirect_to admin_oauth_application_path(@application, anchor: "roles"), notice: "The #{role.name} role was deleted."
  end

  private

  def set_application
    @application = Doorkeeper::Application.find(params[:oauth_application_id])
  end

  def require_superadmin
    return if current_user.superadmin?

    redirect_to admin_oauth_application_path(@application), alert: "Only a superadmin can change the roles of an app."
  end

  def role_params
    params.require(:role).permit(:key, :name, :description)
  end

end
