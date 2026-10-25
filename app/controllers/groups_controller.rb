# frozen_string_literal: true

# The groups a member manages, outside the admin panel. A manager sees the
# members and the open access requests of their group (see GroupPolicy).
class GroupsController < ApplicationController
  RECENT_DECISIONS = 10

  before_action :set_group, only: [:show]
  after_action :verify_authorized, except: [:index]
  after_action :verify_policy_scoped, only: [:index]

  def index
    @groups = policy_scope(Group).order(:name)
    requests = policy_scope(AccessRequest).pending
    @pending_counts = requests.where(group_id: @groups.select(:id)).group(:group_id).count
  end

  def show
    authorize @group
    requests = policy_scope(AccessRequest).where(group: @group).includes(:user, :application)
    @pending_requests = requests.pending.order(:created_at)
    @recent_decisions = requests.where.not(status: "pending").includes(:decided_by).order(decided_at: :desc).limit(RECENT_DECISIONS)
    @memberships = @group.memberships.active.includes(:user).order(:created_at)
    @membership = @group.memberships.build
  end

  private

  def set_group
    @group = Group.find_by!(slug: params[:id])
  end

end
