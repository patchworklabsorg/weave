# frozen_string_literal: true

# The identity team reviews deletion requests (see DeletionReview). The
# review is an authenticity check, not a judgment call, and each request
# shows its due date.
class Admin::DeletionRequestsController < Admin::BaseController
  include IdentityTeamAccess

  RECENT_LIMIT = 20

  before_action :set_request, except: :index

  def index
    @pending = DeletionRequest.pending_review.includes(:user).order(:review_due_at)
    @active = DeletionRequest.where(status: %w[approved running failed]).includes(:user).order(:complete_by)
    @recent = DeletionRequest.where(status: %w[completed rejected cancelled]).includes(:reviewed_by)
                             .order(updated_at: :desc).limit(RECENT_LIMIT)
  end

  def show
    @user = @deletion_request.user
    @runs = @deletion_request.runs
    @categories = DataCategories.all
    @can_review = DeletionReview.can_review?(current_user, @deletion_request)
  end

  def approve
    result = DeletionReview.approve(@deletion_request, by: current_user, note: params[:review_note])
    respond_with_result(result, "The request is approved. The deletion pipeline will run now.")
  end

  def reject
    result = DeletionReview.reject(@deletion_request, by: current_user, note: params[:review_note])
    respond_with_result(result, "The request is rejected. The member was told.")
  end

  def rerun
    if DeletionReview.retry!(@deletion_request, by: current_user)
      redirect_to admin_deletion_request_path(@deletion_request), notice: "The deletion pipeline will run again."
    else
      redirect_to admin_deletion_request_path(@deletion_request), alert: "Only a failed request can run again."
    end
  end

  private

  def set_request
    @deletion_request = DeletionRequest.find_by_public_param!(params[:id])
  end

  def respond_with_result(result, notice)
    if result.success?
      redirect_to admin_deletion_request_path(@deletion_request), notice:
    else
      redirect_to admin_deletion_request_path(@deletion_request), alert: result.errors.values.flatten.to_sentence
    end
  end

end
