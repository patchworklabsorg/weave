# frozen_string_literal: true

class Admin::OauthApplicationsController < Admin::BaseController
  before_action :set_application, only: [:show, :edit, :update, :destroy, :regenerate_secret, :access_policy]
  before_action :require_superadmin, only: [:access_policy]

  def index
    @applications = Doorkeeper::Application.order(created_at: :desc)
  end

  def show
    @access_grants = ApplicationAccessGrant.for_application(@application).includes(:grantee).order(:grantee_type, :created_at)
    @grantable_groups = Group.where.not(id: @access_grants.select { |grant| grant.grantee_type == "Group" }.map(&:grantee_id)).order(:name)
    @roles = ApplicationRole.for_application(@application).includes(assignments: :assignee).order(:key)
    @groups = Group.order(:name)
  end

  def new
    @application = Doorkeeper::Application.new
  end

  def create
    @application = Doorkeeper::Application.new(application_params)

    if @application.save
      flash[:notice] = "OAuth application was successfully created."
      redirect_to admin_oauth_application_path(@application)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @application.update(application_params)
      redirect_to admin_oauth_application_path(@application), notice: "OAuth application was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @application.destroy
    redirect_to admin_oauth_applications_path, notice: "OAuth application was successfully deleted."
  end

  def regenerate_secret
    Rails.logger.info "Regenerating secret for application #{@application.id}"

    begin
      # Use Doorkeeper's method to regenerate the secret if available
      if @application.respond_to?(:renew_secret)
        @application.renew_secret
      else
        # Fallback to manual generation
        @application.secret = Doorkeeper::OAuth::Helpers::UniqueToken.generate
      end

      if @application.save
        @application.reload # Ensure we have the fresh data
        Rails.logger.info "Secret regenerated successfully for application #{@application.id}"
        flash[:notice] = "Client secret has been regenerated. Please update your application with the new secret."
      else
        Rails.logger.error "Failed to save regenerated secret for application #{@application.id}: #{@application.errors.full_messages}"
        flash[:alert] = "Failed to regenerate secret: #{@application.errors.full_messages.join(', ')}"
      end
    rescue => e
      Rails.logger.error "Error regenerating secret for application #{@application.id}: #{e.message}"
      flash[:alert] = "An error occurred while regenerating the secret."
    end

    redirect_to admin_oauth_application_path(@application)
  end

  # Opens an app to everyone or limits it to its access grants (see AppAccess).
  # Superadmin only: this decides who can sign in to the app.
  def access_policy
    policy = params.require(:access_policy)
    unless %w[everyone restricted].include?(policy)
      return redirect_to(admin_oauth_application_path(@application), alert: "Unknown access policy.")
    end

    @application.update!(access_policy: policy)
    RevokeLostAppAccessJob.perform_later(application_id: @application.id) if policy == "restricted"
    redirect_to admin_oauth_application_path(@application),
                notice: policy == "restricted" ? "Only users with an access grant can use this app now." : "Everyone can use this app now."
  end

  private

  def require_superadmin
    return if current_user.superadmin?

    redirect_to admin_oauth_application_path(@application), alert: "Only a superadmin can change who can use an app."
  end

  def set_application
    @application = Doorkeeper::Application.find(params[:id])
  end

  def application_params
    params.require(:doorkeeper_application).permit(:name, :redirect_uri, :scopes, :confidential)
  end

end
