# frozen_string_literal: true

# Adds entries to a member's Thread Count ledger, and reverses them (see
# ThreadCount::Ledger for the rules).
#
# - A vouch: from the signed-in admin, or recorded on behalf of a board member
#   or member who has no admin access.
# - A deduction (a moderation case, a denied or blacklisted project): only for
#   members below the admin's own access level.
# - An external signal or a project outcome typed in by hand.
#
# Nobody adds or reverses an entry about their own account.
class Admin::UserThreadCountEntriesController < Admin::BaseController
  before_action :set_user
  before_action :ensure_can_view_user
  before_action :refuse_own_account

  def create
    result = params[:kind] == "vouch" ? vouch : record
    if result.success?
      redirect_to admin_user_thread_count_path(@user), notice: "Recorded the Thread Count entry for #{@user.full_name}."
    else
      redirect_to admin_user_thread_count_path(@user), alert: "Not recorded: #{result.errors.to_sentence}"
    end
  end

  def reverse
    entry = ThreadCount::Entry.find_by_public_param!(params[:id])
    raise ActiveRecord::RecordNotFound unless entry.user_id == @user.id

    reason = params[:reason].to_s.strip
    result = if reason.empty?
               ThreadCount::Ledger::Result.new(entry: nil, errors: ["Say why you reverse it."])
             else
               ThreadCount::Ledger.reverse(entry, by: current_user, reason:)
             end

    if result.success?
      redirect_to admin_user_thread_count_path(@user), notice: "Reversed the entry."
    else
      redirect_to admin_user_thread_count_path(@user), alert: "Not reversed: #{result.errors.to_sentence}"
    end
  end

  private

  def vouch
    voucher = find_voucher
    return ThreadCount::Ledger::Result.new(entry: nil, errors: ["No Weave account matches the voucher."]) unless voucher

    ThreadCount::Ledger.vouch(subject: @user, voucher:, recorded_by: current_user, reason: params[:reason],
                              evidence_url: params[:evidence_url], renew: params[:renew] == "1")
  end

  def record
    kind, level = params[:kind].to_s.split(":", 2)
    if ThreadCount::Ledger::DEDUCTION_KINDS.include?(kind) && !UserAdminPermissions.new(current_user, @user).manage?
      return ThreadCount::Ledger::Result.new(entry: nil, errors: ["You can only record a deduction for users below your own access level."])
    end

    ThreadCount::Ledger.record(subject: @user, kind:, level:, recorded_by: current_user, reason: params[:reason],
                               evidence_url: params[:evidence_url])
  end

  # Blank means the signed-in admin. Otherwise a Weave ID or an email.
  def find_voucher
    value = params[:voucher].to_s.strip
    return current_user if value.empty?

    User.find_by(p_id: value.upcase) || User.find_for_any_email(value)
  end

  def set_user
    @user = User.find_by!(p_id: params[:user_id])
  end

  def ensure_can_view_user
    return if UserAdminPermissions.new(current_user, @user).view?

    redirect_to admin_users_path, alert: "You don't have permission to view this user"
  end

  def refuse_own_account
    return unless @user == current_user

    redirect_to admin_user_path(@user), alert: "You can't add or reverse Thread Count entries on your own account."
  end

end
