# frozen_string_literal: true

# The member's own demographics form (see DemographicsVault). The member can
# answer, answer again, or take their answers back. The form always starts
# empty: Weave has no way to read the answers back, not even for the member.
class DemographicsController < ApplicationController
  # An admin who impersonates a member must not answer for them or take their
  # answers back.
  before_action :refuse_impersonation

  def show
    @answered_at = DemographicsVault.answered_at(current_user)
    @available = DemographicsVault.available?
  end

  def update
    return redirect_to(demographics_path, alert: t("demographics.form.unavailable")) unless DemographicsVault.available?

    answers = submitted_answers
    result = DemographicsVault.record(current_user, answers, consent: params[:consent] == "1")
    if result.success?
      redirect_to profile_path, notice: t("demographics.form.saved")
    else
      @answered_at = DemographicsVault.answered_at(current_user)
      @available = true
      @form_errors = result.errors
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    DemographicsVault.withdraw!(current_user)
    redirect_to profile_path, notice: t("demographics.form.withdrawn")
  end

  private

  # The answers from the form. A malformed "demographics" param counts as no
  # answers, not as a server error.
  def submitted_answers
    raw = params[:demographics]
    raw.is_a?(ActionController::Parameters) ? raw.permit(*DemographicsVault.permitted_params) : {}
  end

  def refuse_impersonation
    redirect_to profile_path, alert: t("demographics.form.impersonating") if impersonating?
  end

end
