# frozen_string_literal: true

# Groups in the admin panel.
#
# Any admin may look at groups. Only a superadmin may change them, because a
# group membership will grant access to OAuth apps: adding someone to a group
# is a grant of access, the same as an app permission. System groups follow
# user attributes, so nobody may rename or delete them here.
class Admin::GroupsController < Admin::BaseController
  before_action :set_group, only: [:show, :edit, :update, :destroy]
  before_action :require_superadmin, except: [:index, :show]
  before_action :require_editable_group, only: [:edit, :update, :destroy]

  def index
    @groups = Group.order(:name)
    @member_counts = Group::Membership.active.group(:group_id).count
  end

  def show
    @memberships = @group.memberships.includes(:user, :added_by).order(:created_at)
    @membership = @group.memberships.build
  end

  def new
    @group = Group.new
  end

  def create
    @group = Group.new(group_params.merge(kind: "manual", created_by: current_user))

    if @group.save
      redirect_to admin_group_path(@group), notice: "Group was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @group.update(group_params.except(:slug))
      redirect_to admin_group_path(@group), notice: "Group was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @group.destroy
    redirect_to admin_groups_path, notice: "Group was deleted. Its members were removed."
  end

  private

  def set_group
    @group = Group.find_by!(slug: params[:id])
  end

  def group_params
    params.require(:group).permit(:name, :slug, :description)
  end

  def require_superadmin
    return if current_user.superadmin?

    redirect_to admin_groups_path, alert: "Only a superadmin can change groups."
  end

  def require_editable_group
    return if @group.editable?

    redirect_to admin_group_path(@group), alert: "System groups follow user attributes and can't be changed by hand."
  end

end
