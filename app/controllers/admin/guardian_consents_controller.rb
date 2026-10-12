# frozen_string_literal: true

# The review queue for guardian consents with a flag (see
# GuardianConsentSignals). An admin contacts the guardian, then marks the
# consent as checked, or a superadmin revokes it from the user's page.
class Admin::GuardianConsentsController < Admin::BaseController
  RECENT_LIMIT = 20

  def index
    @queue = GuardianConsent.needs_review.includes(:user).order(:granted_at)
    @recent = GuardianConsent.where.not(reviewed_at: nil).includes(:user, :reviewed_by)
                             .order(reviewed_at: :desc).limit(RECENT_LIMIT)
  end

  def review
    consent = GuardianConsent.find(params[:id])
    unless UserAdminPermissions.new(current_user, consent.user).manage?
      redirect_to admin_guardian_consents_path, alert: "You can only check consents for users below your own access level"
      return
    end

    note = params[:note].to_s.strip
    if note.blank?
      redirect_to admin_guardian_consents_path, alert: "Say how you confirmed the consent."
    elsif GuardianConsentFlow.review(consent, by: current_user, note:)
      redirect_to admin_guardian_consents_path, notice: "Marked the consent for #{consent.user.full_name} as checked."
    else
      redirect_to admin_guardian_consents_path, alert: "This consent does not need a check."
    end
  end

end
