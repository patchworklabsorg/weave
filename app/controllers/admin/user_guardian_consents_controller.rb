# frozen_string_literal: true

# Admin tools for a member's parent or guardian consent (see GuardianConsent):
# send the request again, record consent given on paper, or revoke it.
# Recording and revoking decide who can use apps, so they are superadmin only.
class Admin::UserGuardianConsentsController < Admin::BaseController
  before_action :set_user
  before_action :ensure_can_manage_user
  before_action :require_superadmin, only: [:create, :revoke, :verify]
  before_action :set_consent, only: [:resend, :revoke, :verify]

  # Consent the guardian gave outside Weave, for example on a paper form.
  def create
    if @user == current_user
      redirect_to admin_user_path(@user), alert: "You can't record consent for your own account."
      return
    end

    result = GuardianConsentFlow.record_offline(
      @user,
      guardian_name: params[:guardian_name].to_s, guardian_email: params[:guardian_email].to_s,
      recorded_by: current_user, note: params[:note].to_s.strip
    )
    if result.success?
      redirect_to admin_user_path(@user), notice: "Recorded guardian consent for #{@user.full_name}."
    else
      redirect_to admin_user_path(@user), alert: "Consent not recorded: #{result.consent.errors.full_messages.to_sentence}."
    end
  end

  def resend
    if GuardianConsentFlow.resend(@consent)
      redirect_to admin_user_path(@user), notice: "Sent the consent request to #{@consent.guardian_email} again."
    else
      redirect_to admin_user_path(@user), alert: "The request was sent a few minutes ago, or it is no longer pending."
    end
  end

  def revoke
    if GuardianConsentFlow.revoke(@consent, by: current_user)
      redirect_to admin_user_path(@user), notice: "Revoked the guardian consent for #{@user.full_name}."
    else
      redirect_to admin_user_path(@user), alert: "This consent is not granted, so there is nothing to revoke."
    end
  end

  # A signed guardian form and a call or video check with the guardian. Apps
  # read it as `guardian_verified` (see GuardianConsent#verified?).
  def verify
    note = params[:note].to_s.strip
    if note.blank?
      redirect_to admin_user_path(@user), alert: "Say where the signed form is and how you spoke with the guardian."
    elsif GuardianConsentFlow.verify(@consent, by: current_user, note:)
      redirect_to admin_user_path(@user), notice: "Recorded a verified guardian for #{@user.full_name}."
    else
      redirect_to admin_user_path(@user), alert: "Only a granted consent that is not verified yet can be verified."
    end
  end

  private

  def set_user
    @user = User.find_by!(p_id: params[:user_id])
  end

  def set_consent
    # GuardianConsent.find reads the public id; a relation's find would not.
    @consent = GuardianConsent.find_by_public_param!(params[:id])
    raise ActiveRecord::RecordNotFound unless @consent.user_id == @user.id
  end

  def ensure_can_manage_user
    return if UserAdminPermissions.new(current_user, @user).manage?

    redirect_to admin_users_path, alert: "You can only manage users below your own access level"
  end

  def require_superadmin
    return if current_user.superadmin?

    redirect_to admin_user_path(@user), alert: "Only superadmins can perform this action"
  end

end
