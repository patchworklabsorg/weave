# frozen_string_literal: true

# The member asks to delete their account (see DeletionReview). A human on
# the identity team reviews every request before the pipeline runs.
class DeletionRequestsController < ApplicationController
  # An admin who impersonates a member must not ask to delete the account.
  before_action :refuse_impersonation, only: %i[create destroy]

  def show
    load_page
  end

  def create
    unless params[:understand] == "1" && params[:confirmation].to_s.strip.casecmp?(t("data_handling.deletion.confirm_word"))
      @form_errors = { confirmation: t("data_handling.deletion.errors.confirmation") }
      load_page
      return render :show, status: :unprocessable_content
    end

    result = DeletionReview.request!(current_user)
    if result.success?
      redirect_to deletion_request_path, notice: t("data_handling.deletion.requested")
    else
      @form_errors = { base: result.errors.values.flatten.to_sentence }
      load_page
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    request = current_user.deletion_requests.unfinished.order(:created_at).last
    if request && DeletionReview.cancel!(request)
      redirect_to deletion_request_path, notice: t("data_handling.deletion.cancelled")
    else
      redirect_to deletion_request_path, alert: t("data_handling.deletion.errors.cannot_cancel")
    end
  end

  private

  def load_page
    @deletion_request = current_user.deletion_requests.unfinished.order(:created_at).last
    @categories = DataCategories.all
  end

  def refuse_impersonation
    redirect_to deletion_request_path, alert: t("data_handling.impersonating") if impersonating?
  end

end
