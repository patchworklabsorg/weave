# frozen_string_literal: true

# Gives a user or a group access to a restricted OAuth app, or takes it away.
# Superadmin only: a grant decides who can sign in to the app.
class Admin::OauthApplicationAccessGrantsController < Admin::BaseController
  before_action :set_application
  before_action :require_superadmin

  def create
    grantee = find_grantee
    return redirect_to(admin_oauth_application_path(@application), alert: grantee_not_found_message) unless grantee

    grant = ApplicationAccessGrant.new(application: @application, grantee: grantee, created_by: current_user)

    if grant.save
      redirect_to admin_oauth_application_path(@application), notice: "#{grantee_label(grantee)} can use #{@application.name} now."
    else
      redirect_to admin_oauth_application_path(@application), alert: grant.errors.full_messages.to_sentence
    end
  end

  def destroy
    grant = ApplicationAccessGrant.for_application(@application).find(params[:id])
    grant.destroy!
    redirect_to admin_oauth_application_path(@application),
                notice: "Access for #{grantee_label(grant.grantee)} was removed."
  end

  private

  def set_application
    @application = Doorkeeper::Application.find(params[:oauth_application_id])
  end

  def require_superadmin
    return if current_user.superadmin?

    redirect_to admin_oauth_application_path(@application), alert: "Only a superadmin can change who can use an app."
  end

  def grant_params
    params.require(:access_grant).permit(:group_id, :email)
  end

  def find_grantee
    if grant_params[:group_id].present?
      Group.find_by(id: grant_params[:group_id])
    elsif grant_params[:email].present?
      User.find_for_any_email(grant_params[:email])
    end
  end

  def grantee_not_found_message
    grant_params[:group_id].present? ? "That group doesn't exist." : "No user has that email address."
  end

  def grantee_label(grantee)
    grantee.is_a?(Group) ? "The #{grantee.name} group" : grantee.full_name
  end

end
