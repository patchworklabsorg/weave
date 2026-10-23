# frozen_string_literal: true

# A member's Thread Count, the internal trust score (see ThreadCount).
#
# Every admin who may view the member sees the score and may add entries.
# Only superadmins and owners see the entries the score is made of.
class Admin::UserThreadCountsController < Admin::BaseController
  before_action :set_user
  before_action :ensure_can_view_user
  before_action :refuse_own_account

  def show
    if current_user.superadmin?
      @composition = ThreadCount.lines(@user, preload: true)
      @score = @composition.sum(&:contribution).round(2)
    else
      @score = ThreadCount.score(@user)
    end
    @own_vouch = ThreadCount::Ledger.active_vouch(@user, current_user)
    @manual_kinds = manual_kind_options
  end

  private

  def set_user
    @user = User.find_by!(p_id: params[:user_id])
  end

  def ensure_can_view_user
    return if UserAdminPermissions.new(current_user, @user).view?

    redirect_to admin_users_path, alert: "You don't have permission to view this user"
  end

  # Nobody sees their own score, staff included: a visible score is a score
  # people optimize.
  def refuse_own_account
    return unless @user == current_user

    redirect_to admin_user_path(@user), alert: "You can't view your own Thread Count."
  end

  # [label, "kind" or "kind:level"] for the record form.
  def manual_kind_options
    ThreadCount::Ledger::MANUAL_KINDS.flat_map do |kind|
      levels = ThreadCount.config.levels(kind)
      if levels.empty?
        [[helpers.thread_count_label(kind), kind]]
      else
        levels.map { |level| [helpers.thread_count_label(kind, level), "#{kind}:#{level}"] }
      end
    end
  end

end
