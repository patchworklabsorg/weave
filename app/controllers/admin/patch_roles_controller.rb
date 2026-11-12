# frozen_string_literal: true

# Adds a role to a patch, renames it or deletes it (see PatchRole).
# Superadmin only: apps such as Quilt read the role from the `patches` claim,
# so a role can open a patch's finance data.
class Admin::PatchRolesController < Admin::BaseController
  before_action :set_patch
  before_action :require_superadmin
  before_action :set_role, only: [:update, :destroy]

  def create
    role = @patch.roles.new(role_params.merge(created_by: current_user))

    if role.save
      redirect_back_to_roles(notice: "The #{role.name} role was added.")
    else
      redirect_back_to_roles(alert: role.errors.full_messages.to_sentence)
    end
  end

  # Changes the name and the description. The key never changes.
  def update
    if @role.update(role_params.except(:key))
      redirect_back_to_roles(notice: "The #{@role.name} role was updated.")
    else
      redirect_back_to_roles(alert: @role.errors.full_messages.to_sentence)
    end
  end

  def destroy
    @role.destroy!
    redirect_back_to_roles(notice: "The #{@role.name} role was deleted.")
  end

  private

  def set_patch
    @patch = Patch.find_by!(slug: params[:patch_id])
  end

  def set_role
    @role = @patch.roles.find_by_public_param!(params[:id])
  end

  def require_superadmin
    return if current_user.superadmin?

    redirect_to admin_patch_path(@patch), alert: "Only a superadmin can change the roles of a patch."
  end

  def role_params
    params.require(:role).permit(:key, :name, :description)
  end

  def redirect_back_to_roles(**flash)
    redirect_to admin_patch_path(@patch, anchor: "roles"), **flash
  end

end
