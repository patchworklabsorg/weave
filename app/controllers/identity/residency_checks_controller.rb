# frozen_string_literal: true

# The identity team's side of the US residency check without a call (see
# ResidencyFlow): the queue, pre-review and the decision. Checks on an
# identity call are decided on the verification page.
class Identity::ResidencyChecksController < Identity::BaseController
  include SecureImageResponse

  RECENT_LIMIT = 20

  before_action :set_check, except: :index

  def index
    reviews = ResidencyCheck.document_reviews.includes(:user)
    @submitted = reviews.submitted.order(:created_at)
    @in_pre_review = reviews.pre_review.includes(:pre_reviewer).order(:pre_review_started_at)
    @recent = reviews.where(status: %w[decided needs_resubmission]).where.not(evidence_type: ResidencyCheck::MEMBER_STATEMENT)
                     .includes(:decided_by).order(updated_at: :desc).limit(RECENT_LIMIT)
  end

  def show
    @user = @check.user
  end

  def start_pre_review
    if ResidencyFlow.start_pre_review(@check, by: current_user)
      redirect_to identity_residency_check_path(@check), notice: "You took this check for pre-review."
    else
      redirect_to identity_residency_check_path(@check), alert: "This check can't go to pre-review now, or it is your own."
    end
  end

  # The pre-reviewer opens the proof document in the secure viewer.
  def image
    data = ResidencyFlow.pre_review_document(@check, by: current_user)
    if data.nil?
      render_secure_image_error("Only the pre-reviewer can open the document, and only during pre-review.")
      return
    end

    render_secure_image(data:, content_type: @check.document.content_type, subject_id: @check.public_id)
  ensure
    data&.replace("")
  end

  def reject_document
    if ResidencyFlow.reject_document(@check, by: current_user, note: params[:note].to_s.strip)
      redirect_to identity_residency_check_path(@check), notice: "The member was asked for a new document."
    else
      redirect_to identity_residency_check_path(@check), alert: KeyCustody.warning_for_pre_review ||
                                                                "Write what the member must fix. Only the pre-reviewer can send it back."
    end
  end

  def decide
    result = ResidencyFlow.decide_review(@check, by: current_user, us_resident: yes_no(params[:us_resident]),
                                                 us_state: params[:us_state].to_s, evidence_type: params[:evidence_type].to_s)
    if result.success?
      redirect_to identity_residency_check_path(@check), notice: "Recorded the residency result."
    else
      redirect_to identity_residency_check_path(@check),
                  alert: "Result not recorded: #{result.errors.map { |key, message| key == :base ? message : "#{key.to_s.humanize} #{message}" }.join('. ')}."
    end
  end

  private

  def set_check
    @check = ResidencyCheck.find_by_public_param!(params[:id])
  end

  def yes_no(value)
    case value.to_s
    when "yes" then true
    when "no" then false
    end
  end

end
