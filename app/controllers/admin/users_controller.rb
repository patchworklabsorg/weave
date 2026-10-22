# frozen_string_literal: true

class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: [:show, :edit, :update, :destroy, :impersonate, :regen_pid, :invite_to_slack, :code_of_conduct_exemption]
  before_action :ensure_can_view_user, only: [:show]
  before_action :ensure_can_manage_user, only: [:edit, :update, :destroy, :regen_pid]
  before_action :ensure_can_impersonate, only: [:impersonate]
  before_action :ensure_not_already_impersonating, only: [:impersonate]
  before_action :require_superadmin, only: [:regen_pid, :code_of_conduct_exemption]
  skip_before_action :authenticate_user!, only: [:stop_impersonating]
  skip_before_action :require_admin, only: [:stop_impersonating]
  helper_method :admin_permissions_for

  def index
    @users = User.all

    if params[:search].present?
      search_term = "%#{User.sanitize_sql_like(params[:search].strip)}%"
      @users = @users.where(
        "first_name ILIKE :t OR last_name ILIKE :t OR email ILIKE :t OR p_id ILIKE :t OR (first_name || ' ' || last_name) ILIKE :t",
        t: search_term
      )
    end

    @users = @users.order(created_at: :desc)
  end

  def show
    @impersonations = Impersonation.where(user: @user).includes(:admin).recent_first.limit(50)
    @impersonation_action_counts = Impersonation::Action.where(impersonation: @impersonations).group(:impersonation_id).count
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    @user.skip_signup_blocklist = true
    privileged_attributes_allowed = assign_privileged_attributes

    # New users sign in by magic link. The model requires a password, so give
    # them a random one unless a superadmin set one.
    if @user.password.nil?
      random_password = User.generate_secure_password
      @user.password = random_password
      @user.password_confirmation = random_password
    end

    if privileged_attributes_allowed && @user.save
      redirect_to admin_users_path, notice: "User was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    @user.assign_attributes(user_params)

    if assign_privileged_attributes && @user.valid? && reset_directory_password && @user.save
      # Pushed from here, not a model callback, so the Slack sync's own
      # writes are not sent back to Slack.
      PushSlackProfileFieldsJob.perform_later(@user.id) if @user.slack_profile_fields_need_push?
      redirect_to admin_user_path(@user), notice: "User was successfully updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @user == current_user
      redirect_to admin_users_path, alert: "You cannot delete yourself."
    else
      @user.destroy
      redirect_to admin_users_path, notice: "User was successfully deleted."
    end
  end

  def impersonate
    Rails.logger.info "Attempting to impersonate user #{@user.id} as admin #{current_user.id}"

    if @user.is_impersonatable?(current_user)
      Rails.logger.info "Impersonation allowed, setting session variables"
      impersonation = Impersonation.start!(admin: current_user, user: @user, request: request)
      session[:admin_id] = current_user.id
      session[:user_id] = @user.id
      session[:impersonation_id] = impersonation.id
      Rails.logger.info "Session set: admin_id=#{session[:admin_id]}, user_id=#{session[:user_id]}"

      # Clear the current_user cache to force reload
      @current_user = nil

      flash[:notice] = "Now impersonating #{@user.full_name}"
      redirect_to root_path
    else
      Rails.logger.warn "Impersonation denied for user #{@user.id} by admin #{current_user.id}"
      Impersonation.start!(admin: current_user, user: @user, request: request, denied: true)
      redirect_to admin_users_path, alert: "Cannot impersonate this user"
    end
  end

  def stop_impersonating
    Rails.logger.info "Stop impersonating called. Current session: admin_id=#{session[:admin_id]}, user_id=#{session[:user_id]}"

    if session[:admin_id]
      admin_user = User.find(session[:admin_id])
      Rails.logger.info "Found admin user: #{admin_user.full_name} (#{admin_user.id})"

      end_impersonation("stopped")
      session[:user_id] = session[:admin_id]
      session.delete(:admin_id)

      Rails.logger.info "Session reset. New session: admin_id=#{session[:admin_id]}, user_id=#{session[:user_id]}"
      redirect_to admin_root_path, notice: "Stopped impersonating. Welcome back, #{admin_user.full_name}!"
    else
      Rails.logger.warn "No admin_id in session, cannot stop impersonating"
      redirect_to admin_root_path, alert: "You are not currently impersonating anyone"
    end
  end

  def regen_pid
    old_pid = @user.p_id
    new_pid = @user.regen_pid

    Rails.logger.info "Owner #{current_user.email} regenerated p_id for user #{@user.email}: #{old_pid} -> #{new_pid}"

    redirect_to admin_user_path(@user), notice: "Successfully regenerated p_id from #{old_pid} to #{new_pid}"
  rescue => e
    Rails.logger.error "Failed to regenerate p_id for user #{@user.email}: #{e.message}"
    redirect_to admin_user_path(@user), alert: "Failed to regenerate p_id: #{e.message}"
  end

  def invite_to_slack
    resend = @user.slack_invited_at.present?
    InviteToSlackJob.perform_later(@user.id, resend: resend)
    verb = resend ? "Re-invited" : "Invited"
    redirect_to admin_user_path(@user), notice: "#{verb} #{@user.email} to Slack (queued)."
  end

  # Lets one user use apps without accepting the code of conduct, or takes
  # that away (see AppAccess). Superadmin only: this decides who can sign in to
  # apps.
  def code_of_conduct_exemption
    exempt = ActiveModel::Type::Boolean.new.cast(params.require(:exempt))
    @user.update!(code_of_conduct_exempt: exempt)
    RevokeLostAppAccessJob.perform_later(user_id: @user.id) unless exempt
    redirect_to admin_user_path(@user),
                notice: exempt ? "#{@user.full_name} can use apps without accepting the Code of Conduct." : "#{@user.full_name} must accept the Code of Conduct to use apps."
  end

  private

  def ensure_can_impersonate
    return if current_user.superadmin? && current_user.can_impersonate?

    Impersonation.start!(admin: current_user, user: @user, request: request, denied: true)
    redirect_to admin_users_path, alert: "You don't have permission to impersonate users"
  end

  def ensure_not_already_impersonating
    return unless impersonating?

    redirect_to admin_users_path, alert: "You cannot impersonate while already impersonating another user. Stop impersonating first."
  end

  def set_user
    @user = User.find_by!(p_id: params[:id])
  end

  def require_superadmin
    return if current_user&.superadmin?

    redirect_to admin_users_path, alert: "Only superadmins can perform this action"
  end

  def admin_permissions_for(user)
    UserAdminPermissions.new(current_user, user)
  end

  def ensure_can_view_user
    return if admin_permissions_for(@user).view?

    redirect_to admin_users_path, alert: "You don't have permission to view this user"
  end

  def ensure_can_manage_user
    return if admin_permissions_for(@user).manage?

    redirect_to admin_users_path, alert: "You can only manage users below your own access level"
  end

  # Fields any admin who may manage the target can set. Role and password are
  # deliberately absent: see assign_privileged_attributes.
  def user_params
    params.require(:user).permit(
      :first_name, :last_name, :legal_first_name, :legal_last_name, :email, :pronouns, :phone_number, :birthday,
      # Membership attribute flags (configure capabilities, not access)
      :is_staff, :is_contractor, :is_board,
      # Manager relationship
      :manager_id,
      # Slack API-editable fields
      :slack_title, :slack_city, :slack_state, :slack_country,
      :slack_organization, :slack_division, :slack_department, :slack_cost_center
    )
  end

  # Role and password are read outside the permit list because what may be
  # assigned depends on who is acting on whom (UserAdminPermissions). A request
  # asking for more than that is rejected as a whole rather than partly applied.
  # Returns false, with errors on @user, when rejected.
  def assign_privileged_attributes
    submitted = params.require(:user)
    permissions = admin_permissions_for(@user)
    requested_role = submitted[:role]

    if submitted.key?(:role) && requested_role.to_s != @user.role
      return reject_privileged_change(:role, "is not one you can assign") unless permissions.assign_role?(requested_role)

      @user.role = requested_role.to_s
    end

    if submitted[:password].present?
      return reject_privileged_change(:password, "can only be set by a superadmin or owner who outranks this user") unless permissions.change_password?

      if @user.persisted? && directory_password_user?
        # AD holds this user's password (see DirectoryPasswords). It goes to
        # AD in #reset_directory_password, never to the Weave database.
        unless submitted[:password].to_s == submitted[:password_confirmation].to_s
          @user.errors.add(:password_confirmation, "doesn't match Password")
          return false
        end
        @directory_password = submitted[:password].to_s
      else
        @user.password = submitted[:password].to_s
        @user.password_confirmation = submitted[:password_confirmation].to_s
      end
    end

    true
  end

  def directory_password_user?
    DirectoryPasswords.directory_user?(@user)
  rescue ActiveDirectory::Unavailable
    # Fail closed: without AD, Weave can't tell whether the password lives
    # there, so it sets neither (see #reset_directory_password).
    @directory_unavailable = true
    true
  end

  # An admin reset is a replace as the service account. Runs after the other
  # fields validate and before they save, so an AD refusal saves nothing.
  def reset_directory_password
    if @directory_unavailable
      @user.errors.add(:password, "was not changed: Weave can't reach Active Directory now")
      return false
    end
    return true if @directory_password.nil?

    status = DirectoryPasswords.reset(@user, @directory_password)
    @directory_password = nil
    return true if status == :ok

    message = status == :policy_rejected ? "does not meet the Active Directory password policy" : "was not changed: Active Directory refused it (#{status})"
    @user.errors.add(:password, message)
    false
  end

  def reject_privileged_change(attribute, message)
    Rails.logger.warn "Admin #{current_user.id} was refused a #{attribute} change on user #{@user.id || 'new'}"
    @user.errors.add(attribute, message)
    false
  end

end
