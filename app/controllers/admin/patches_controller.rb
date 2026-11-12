# frozen_string_literal: true

# Patches in the admin panel (see Patch).
#
# Any admin may look at patches. Only a superadmin may create a patch or
# change its name and description, like groups. The slug never changes, and
# there is no delete: role assignments, Quilt and app tokens name the slug.
#
# The show page lists the patch leads, the patch's own roles with who holds
# them, and the apps linked to the patch. A patch lead changes through
# identity governance. The patch's own roles change through
# Admin::PatchRolesController and Admin::PatchRoleAssignmentsController
# (superadmin only).
class Admin::PatchesController < Admin::BaseController
  before_action :set_patch, only: [:show, :edit, :update]
  before_action :require_superadmin, except: [:index, :show]

  def index
    @patches = Patch.order(:name)
    @application_counts = Doorkeeper::Application.where.not(patch_id: nil).group(:patch_id).count
  end

  def show
    @applications = @patch.applications.order(:name)
    @leads = RoleGrants.assignments("patch_lead").where(scope: @patch.slug).includes(:granted_by).to_a
    @roles = @patch.roles.includes(assignments: :assignee).order(:key)
    # Only a manual group can hold a patch role (see PatchRoleAssignment).
    @groups = Group.manual.order(:name) if current_user.superadmin?
  end

  def new
    @patch = Patch.new
  end

  def create
    @patch = Patch.new(patch_params.merge(created_by: current_user))

    if @patch.save
      redirect_to admin_patch_path(@patch), notice: "The patch was created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @patch.update(patch_params.except(:slug))
      redirect_to admin_patch_path(@patch), notice: "The patch was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  def set_patch
    @patch = Patch.find_by!(slug: params[:id])
  end

  def patch_params
    params.require(:patch).permit(:name, :slug, :description)
  end

  def require_superadmin
    return if current_user.superadmin?

    redirect_to admin_patches_path, alert: "Only a superadmin can change patches."
  end

end
