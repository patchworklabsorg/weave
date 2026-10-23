# frozen_string_literal: true

class Admin::OauthApplicationsController < Admin::BaseController
  before_action :set_application, only: [:show, :edit, :update, :destroy, :regenerate_secret, :access_policy, :code_of_conduct, :guardian_consent, :email_domains]
  before_action :require_superadmin, only: [:access_policy, :code_of_conduct, :guardian_consent, :email_domains]
  # The response holds a working client secret, which lets its holder act as
  # the app (an `introspect` app included). Only a superadmin may get one.
  before_action :require_superadmin_for_secret, only: [:regenerate_secret]

  def index
    @applications = Doorkeeper::Application.order(created_at: :desc)
    return if params[:search].blank?

    term = "%#{Doorkeeper::Application.sanitize_sql_like(params[:search].to_s.strip)}%"
    @applications = @applications.where("name ILIKE :t OR uid ILIKE :t OR redirect_uri ILIKE :t", t: term)
  end

  def show
    load_show_data
  end

  def new
    @application = Doorkeeper::Application.new
  end

  def create
    @application = Doorkeeper::Application.new(application_params)

    if introspect_change_allowed? && @application.save
      show_secret_once("OAuth application was successfully created. Copy the client secret now: Weave shows it only once.")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    @application.assign_attributes(application_params)

    if introspect_change_allowed? && @application.save
      redirect_to admin_oauth_application_path(@application), notice: "OAuth application was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @application.destroy
    redirect_to admin_oauth_applications_path, notice: "OAuth application was successfully deleted."
  end

  # Weave stores client secrets hashed (hash_application_secrets), so the
  # plaintext exists only in memory right after it is generated. Render it in
  # this response; never redirect, and never show the stored value, which is
  # the hash and does not work as a secret.
  def regenerate_secret
    unless @application.confidential?
      return redirect_to(admin_oauth_application_path(@application), alert: "A public app has no client secret.")
    end

    Rails.logger.info "Regenerating secret for application #{@application.id}"
    @application.renew_secret

    if @application.save
      Rails.logger.info "Secret regenerated for application #{@application.id}"
      show_secret_once("Client secret regenerated. Copy it now: Weave shows it only once. Update the app with it.")
    else
      Rails.logger.error "Failed to save regenerated secret for application #{@application.id}: #{@application.errors.full_messages}"
      redirect_to admin_oauth_application_path(@application),
                  alert: "Failed to regenerate secret: #{@application.errors.full_messages.join(', ')}"
    end
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

  # Opts an app out of the code-of-conduct requirement, or back in (see
  # AppAccess). Superadmin only: this decides who can sign in to the app.
  def code_of_conduct
    required = ActiveModel::Type::Boolean.new.cast(params.require(:required))
    @application.update!(requires_code_of_conduct: required)
    RevokeLostAppAccessJob.perform_later(application_id: @application.id) if required
    redirect_to admin_oauth_application_path(@application),
                notice: required ? "This app now requires the Code of Conduct." : "This app no longer requires the Code of Conduct."
  end

  # Opts an app out of the guardian consent requirement for members under 18,
  # or back in (see AppAccess). Superadmin only, like #code_of_conduct.
  def guardian_consent
    required = ActiveModel::Type::Boolean.new.cast(params.require(:required))
    @application.update!(requires_guardian_consent: required)
    RevokeLostAppAccessJob.perform_later(application_id: @application.id) if required
    redirect_to admin_oauth_application_path(@application),
                notice: required ? "Members under 18 now need guardian consent to use this app." : "Members under 18 can now use this app without guardian consent."
  end

  # Sets the domains the app's `email` claim must come from (see
  # AppAccess.email_for). Google Workspace needs this. Superadmin only: users
  # without an address on these domains lose access.
  def email_domains
    domains = params[:email_domains].to_s.split(/[\s,]+/).map { |domain| domain.strip.downcase.delete_prefix("@") }.compact_blank.uniq
    invalid = domains.grep_v(/\A[a-z0-9-]+(\.[a-z0-9-]+)+\z/)
    if invalid.any?
      return redirect_to(admin_oauth_application_path(@application), alert: "#{invalid.to_sentence} is not a domain.")
    end

    @application.update!(email_domains: domains)
    RevokeLostAppAccessJob.perform_later(application_id: @application.id) if domains.any?
    redirect_to admin_oauth_application_path(@application),
                notice: domains.any? ? "The email claim now comes from #{domains.to_sentence}." : "The email claim is the primary address again."
  end

  private

  # Renders the show page with the new plaintext secret. no-store keeps it
  # out of the browser and proxy caches.
  def show_secret_once(notice)
    @plaintext_secret = @application.plaintext_secret if @application.confidential?
    response.headers["Cache-Control"] = "no-store"
    flash.now[:notice] = notice
    load_show_data
    render :show
  end

  def load_show_data
    @access_grants = ApplicationAccessGrant.for_application(@application).includes(:grantee).order(:grantee_type, :created_at)
    @grantable_groups = Group.where.not(id: @access_grants.select { |grant| grant.grantee_type == "Group" }.map(&:grantee_id)).order(:name)
    @roles = ApplicationRole.for_application(@application).includes(assignments: :assignee).order(:key)
    @groups = Group.order(:name)
  end

  def require_superadmin
    return if current_user.superadmin?

    redirect_to admin_oauth_application_path(@application), alert: "Only a superadmin can change who can use an app."
  end

  def require_superadmin_for_secret
    return if current_user.superadmin?

    redirect_to admin_oauth_application_path(@application), alert: "Only a superadmin can regenerate a client secret."
  end

  # The `introspect` scope lets an app read the tokens of other apps, so only a
  # superadmin may add or remove it. Other scopes stay open to any admin.
  def introspect_change_allowed?
    return true if current_user.superadmin?

    before = Doorkeeper::OAuth::Scopes.from_string(@application.scopes_was.to_s).exists?("introspect")
    return true if before == @application.scopes.exists?("introspect")

    @application.errors.add(:base, "Only a superadmin can add or remove the introspect scope.")
    false
  end

  # Finds the app by its public id only. A numeric database id is a 404.
  def set_application
    @application = Doorkeeper::Application.find_by_public_param!(params[:id])
  end

  def application_params
    params.require(:doorkeeper_application).permit(:name, :redirect_uri, :scopes, :confidential)
  end

end
