# frozen_string_literal: true

# The member gives or withdraws consent to be counted in one funder's report
# (see FunderConsent). Only funders with requires_member_consent show on the
# demographics page.
class FunderConsentsController < ApplicationController
  before_action :refuse_impersonation
  before_action :set_profile

  def create
    FunderConsent.give!(current_user, @profile.key)
    redirect_to demographics_path, notice: t("funder_consents.given", funder: @profile.name)
  end

  def destroy
    FunderConsent.withdraw!(current_user, @profile.key)
    redirect_to demographics_path, notice: t("funder_consents.withdrawn", funder: @profile.name)
  end

  private

  def set_profile
    @profile = FunderProfiles.find(params[:funder])
    redirect_to demographics_path, alert: t("funder_consents.unknown") unless @profile&.consent_required?
  end

  def refuse_impersonation
    redirect_to demographics_path, alert: t("funder_consents.impersonating") if impersonating?
  end

end
