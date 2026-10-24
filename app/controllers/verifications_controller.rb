# frozen_string_literal: true

# The member's side of identity verification (see VerificationFlow): see the
# status, upload an ID, and upload again after a document problem or after
# the cooldown of a failed call.
class VerificationsController < ApplicationController
  before_action :forbid_impersonation, only: :create

  def show
    load_page
  end

  def create
    unless params[:data_notice_read] == "1"
      @form_errors = { data_notice_read: t("verification.errors.data_notice") }
      return render_page_with_errors
    end
    if params[:id_document].blank? && params[:verification_method].to_s != "digital_id_call"
      @form_errors = { id_document: t("verification.errors.document_missing") }
      return render_page_with_errors
    end

    result = VerificationFlow.submit(
      current_user,
      document: params[:id_document],
      document_type: params[:document_type].to_s,
      verification_method: params[:verification_method].presence || "document_call"
    )
    if result.success?
      redirect_to verification_path, notice: t("verification.submitted")
    else
      @form_errors = result.errors
      render_page_with_errors
    end
  end

  private

  def load_page
    @latest = current_user.latest_verification
    @status = current_user.verification_status
    @blocker = VerificationFlow.submission_blocker(current_user)
    @attempts = current_user.verifications.order(created_at: :desc).to_a
  end

  def render_page_with_errors
    load_page
    render :show, status: :unprocessable_content
  end

  # An admin who impersonates a member must not upload an ID for them.
  def forbid_impersonation
    return unless impersonating?

    redirect_to verification_path, alert: "You can't upload an ID while you impersonate a member."
  end

end
