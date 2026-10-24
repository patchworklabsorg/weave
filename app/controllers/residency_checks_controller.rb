# frozen_string_literal: true

# The member's side of the US residency check without a call (see
# ResidencyFlow): upload a proof document, or say that they do not live in
# the US. The status shows on the verification page.
class ResidencyChecksController < ApplicationController
  before_action :forbid_impersonation

  def create
    result = ResidencyFlow.submit_document(current_user, document: params[:residency_document],
                                                         evidence_type: params[:evidence_type].to_s)
    if result.success?
      redirect_to verification_path, notice: t("residency.submitted")
    else
      redirect_to verification_path, alert: result.errors.values.join(" ")
    end
  end

  def not_resident
    result = ResidencyFlow.declare_non_resident(current_user)
    if result.success?
      redirect_to verification_path, notice: t("residency.declared")
    else
      redirect_to verification_path, alert: result.errors.values.join(" ")
    end
  end

  private

  # An admin who impersonates a member must not upload or answer for them.
  def forbid_impersonation
    return unless impersonating?

    redirect_to verification_path, alert: "You can't change a residency check while you impersonate a member."
  end

end
