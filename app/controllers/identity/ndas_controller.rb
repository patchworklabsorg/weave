# frozen_string_literal: true

# An owner records a signed NDA by hand (see IdentityNda). NDAs are signed in
# Adobe Acrobat Sign, so the form takes the date, the version and the agreement ID.
class Identity::NdasController < Identity::BaseController
  include IdentityGovernanceAccess

  def create
    signed_on = begin
      Date.iso8601(params[:signed_on].to_s)
    rescue Date::Error
      nil
    end
    result = IdentityGovernance.record_nda(find_person(params[:person]), by: current_user, signed_on:,
                                                                        version: params[:nda_version], reference: params[:signature_reference])
    if result.success?
      redirect_to identity_governance_path, notice: "Recorded the NDA of #{result.record.user.full_name}."
    else
      redirect_to identity_governance_path, alert: "Not recorded: #{result.message}."
    end
  end

end
