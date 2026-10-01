# frozen_string_literal: true

class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: [:show, :edit, :update, :destroy, :impersonate, :regen_pid, :invite_to_slack]
  before_action :ensure_can_view_user, only: [:show]
  before_action :ensure_can_manage_user, only: [:edit, :update, :destroy, :regen_pid]
  before_action :ensure_can_impersonate, only: [:impersonate]
  before_action :ensure_not_already_impersonating, only: [:impersonate]
  before_action :require_superadmin, only: [:regen_pid]
  skip_before_action :authenticate_user!, only: [:stop_impersonating]
  skip_before_action :require_admin, only: [:stop_impersonating]
  helper_method :admin_permissions_for

  def index
    @users = User.all

    if params[:search].present?
      search_term = "%#{params[:search]}%"
      @users = @users.where(
        "first_name ILIKE ? OR last_name ILIKE ? OR email ILIKE ? OR p_id ILIKE ?",
        search_term, search_term, search_term, search_term
      )
    end

    @users = @users.order(created_at: :desc)
  end

  def show
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
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
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @user.assign_attributes(user_params)

    if assign_privileged_attributes && @user.save
      redirect_to admin_user_path(@user), notice: "User was successfully updated."
    else
      render :edit, status: :unprocessable_entity
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
      session[:admin_id] = current_user.id
      session[:user_id] = @user.id
      Rails.logger.info "Session set: admin_id=#{session[:admin_id]}, user_id=#{session[:user_id]}"

      # Clear the current_user cache to force reload
      @current_user = nil

      flash[:notice] = "Now impersonating #{@user.full_name}"
      redirect_to root_path
    else
      Rails.logger.warn "Impersonation denied for user #{@user.id} by admin #{current_user.id}"
      redirect_to admin_users_path, alert: "Cannot impersonate this user"
    end
  end

  def stop_impersonating
    Rails.logger.info "Stop impersonating called. Current session: admin_id=#{session[:admin_id]}, user_id=#{session[:user_id]}"

    if session[:admin_id]
      admin_user = User.find(session[:admin_id])
      Rails.logger.info "Found admin user: #{admin_user.full_name} (#{admin_user.id})"

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

  private

  def ensure_can_impersonate
    return if current_user.superadmin? && current_user.can_impersonate?

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
      :first_name, :last_name, :legal_first_name, :legal_last_name, :email, :phone_number, :birthday,
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

      @user.password = submitted[:password].to_s
      @user.password_confirmation = submitted[:password_confirmation].to_s
    end

    true
  end

  def reject_privileged_change(attribute, message)
    Rails.logger.warn "Admin #{current_user.id} was refused a #{attribute} change on user #{@user.id || 'new'}"
    @user.errors.add(attribute, message)
    false
  end

end
