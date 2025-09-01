# frozen_string_literal: true

class Admin::UsersController < Admin::BaseController
  before_action :set_user, only: [:show, :edit, :update, :destroy, :impersonate, :regen_pid]
  before_action :ensure_can_impersonate, only: [:impersonate]
  before_action :ensure_not_already_impersonating, only: [:impersonate]
  before_action :require_owner, only: [:regen_pid]
  skip_before_action :authenticate_user!, only: [:stop_impersonating]
  skip_before_action :require_admin, only: [:stop_impersonating]

  def index
    @users = User.all

    if params[:search].present?
      search_term = "%#{params[:search]}%"
      @users = @users.where(
        "first_name ILIKE ? OR last_name ILIKE ? OR email ILIKE ? OR pd_id ILIKE ?",
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

    if @user.save
      redirect_to admin_users_path, notice: "User was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @user.update(user_params)
      redirect_to admin_users_path, notice: "User was successfully updated."
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
      redirect_to root_path, allow_other_host: true
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
  rescue StandardError => e
    Rails.logger.error "Failed to regenerate p_id for user #{@user.email}: #{e.message}"
    redirect_to admin_user_path(@user), alert: "Failed to regenerate p_id: #{e.message}"
  end

  private

  def ensure_can_impersonate
    return if current_user.can_impersonate?

    redirect_to admin_users_path, alert: "You don't have permission to impersonate users"
  end

  def ensure_not_already_impersonating
    return unless impersonating?

    redirect_to admin_users_path, alert: "You cannot impersonate while already impersonating another user. Stop impersonating first."
  end

  def set_user
    @user = User.find(params[:id])
  end

  def require_owner
    return if current_user&.owner?

    redirect_to admin_users_path, alert: "Only owners can perform this action"
  end

  def user_params
    params.require(:user).permit(:first_name, :last_name, :email, :access_level, :password, :password_confirmation)
  end

end
