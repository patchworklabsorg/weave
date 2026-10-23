# frozen_string_literal: true

# The identity team's side of verification (see VerificationFlow): the queue,
# pre-review, the call outcome and escalations.
class Identity::VerificationsController < Identity::BaseController
  include SecureImageResponse

  RECENT_LIMIT = 20

  before_action :set_verification, except: :index

  def index
    @awaiting_pre_review = Verification.submitted.includes(:user).order(:created_at)
    @in_pre_review = Verification.pre_review.includes(:user, :pre_reviewer).order(:pre_review_started_at)
    @awaiting_call = Verification.awaiting_call.includes(:user).order(:pre_reviewed_at)
    @calls = Verification.call_scheduled.includes(:user).order(:call_scheduled_for)
    @escalations = Verification.escalation_open.includes(:user).order(:escalated_at)
    @recent = Verification.where(status: %w[verified failed needs_resubmission]).includes(:user)
                          .order(updated_at: :desc).limit(RECENT_LIMIT)
  end

  def show
    @user = @verification.user
    @events = @verification.events.includes(:actor)
    @chain = @verification.chain
    @excluded_ids = VerificationFlow.excluded_verifier_ids(@user)
    @team = User.identity_team.where.not(id: [current_user.id, @verification.user_id].compact).order(:first_name)
    @break_glass_records = @verification.break_glass_records.includes(:requested_by, :approvers).order(created_at: :desc)
  end

  def start_pre_review
    if VerificationFlow.start_pre_review(@verification, by: current_user)
      redirect_to identity_verification_path(@verification), notice: "You took this attempt for pre-review."
    else
      redirect_to identity_verification_path(@verification), alert: "This attempt can't go to pre-review now, or it is your own."
    end
  end

  # The pre-reviewer opens the ID image in the secure viewer. Every view is
  # logged. The bytes go only to the viewer script (see SecureImageResponse).
  def image
    data = VerificationFlow.pre_review_document(@verification, by: current_user)
    if data.nil?
      render_secure_image_error("Only the pre-reviewer can open the image, and only during pre-review. " \
                                "Use break-glass for any other access.")
      return
    end

    render_secure_image(data:, content_type: @verification.id_document.content_type, subject_id: @verification.public_id)
  ensure
    data&.replace("")
  end

  def reject_document
    if VerificationFlow.reject_document(@verification, by: current_user, note: params[:note].to_s.strip)
      redirect_to identity_verification_path(@verification), notice: "The member was asked for a new document."
    else
      redirect_to identity_verification_path(@verification), alert: KeyCustody.warning_for_pre_review ||
                                                                    "Write what the member must fix. The attempt must be in pre-review."
    end
  end

  def take_over_pre_review
    if VerificationFlow.take_over_pre_review(@verification, by: current_user)
      redirect_to identity_verification_path(@verification), notice: "You are now the pre-reviewer. The hand-over is logged."
    else
      redirect_to identity_verification_path(@verification),
                  alert: "Only another identity team member can take over, while the attempt is in pre-review."
    end
  end

  def approve_document
    if VerificationFlow.approve_document(@verification, by: current_user)
      redirect_to identity_verification_path(@verification),
                  notice: "Document OK. Agree a call time with the member by email or Slack, then record it here."
    else
      redirect_to identity_verification_path(@verification), alert: KeyCustody.warning_for_pre_review ||
                                                                    "Only the pre-reviewer can mark the document OK, during pre-review."
    end
  end

  def schedule_call
    at = parse_time(params[:call_scheduled_for])
    if VerificationFlow.schedule_call(@verification, by: current_user, at:)
      redirect_to identity_verification_path(@verification), notice: "The call time is recorded. We emailed the member."
    else
      redirect_to identity_verification_path(@verification),
                  alert: "Give a time in the future. The document must be OK first, or the attempt must have a call."
    end
  end

  def decide
    result = VerificationFlow.decide(
      @verification,
      by: current_user,
      outcome: params[:details_mismatch] == "1" ? "failed" : params[:outcome].to_s,
      reason: params[:reason].to_s.strip,
      age_consistent: yes_no(params[:age_consistent]),
      region_consistent: yes_no(params[:region_consistent]),
      second_verifier: (User.identity_team.find_by(p_id: params[:second_verifier]) if params[:second_verifier].present?),
      guardian_attended: params[:guardian_attended] == "1",
      identifiers: identifiers_from_params,
      details_mismatch: params[:details_mismatch] == "1"
    )
    if result.success?
      redirect_to identity_verification_path(@verification), notice: "Recorded the outcome: #{result.verification.status}."
    elsif (@mismatch = result.errors.slice(*VerificationFlow::MISMATCH_KEYS)).any?
      # Show the form again with what the verifier typed (never stored), so
      # they can correct the entry or fail the call.
      @decision_values = decision_form_values
      flash.now[:alert] = mismatch_alert(@mismatch)
      show
      render :show, status: :unprocessable_content
    else
      redirect_to identity_verification_path(@verification),
                  alert: "Outcome not recorded: #{result.errors.map { |key, message| key == :base ? message : "#{key.to_s.humanize} #{message}" }.join('. ')}."
    end
  end

  def resolve_escalation
    if VerificationFlow.resolve_escalation(@verification, by: current_user, resolution: params[:resolution].to_s,
                                                          note: params[:note].to_s.strip)
      redirect_to identity_verification_path(@verification), notice: "The escalation is resolved."
    else
      redirect_to identity_verification_path(@verification), alert: "Only an identity team lead can resolve an escalation, with a note."
    end
  end

  private

  def set_verification
    @verification = Verification.find_by_public_param!(params[:id])
  end

  def yes_no(value)
    case value.to_s
    when "yes" then true
    when "no" then false
    end
  end

  def parse_time(value)
    Time.zone.parse(value.to_s) if value.present?
  rescue ArgumentError
    nil
  end

  # What the verifier typed in the outcome form, to show it again after a
  # name or birthday mismatch. It is never stored.
  def decision_form_values
    {
      second_verifier: params[:second_verifier].to_s, guardian_attended: params[:guardian_attended] == "1",
      age_consistent: params[:age_consistent].to_s, region_consistent: params[:region_consistent].to_s,
      reason: params[:reason].to_s,
      identifiers: params[:identifiers].respond_to?(:permit) ? params[:identifiers].permit(*VerificationIdentifiers.members).to_h.symbolize_keys : {}
    }
  end

  # Says which field differs, never the account value.
  def mismatch_alert(mismatch)
    fields = []
    fields << "legal name" if mismatch.key?(:identifiers_legal_name)
    fields << "birthday" if mismatch.key?(:identifiers_date_of_birth)
    "Outcome not recorded: the #{fields.join(' and ')} you typed #{fields.size > 1 ? 'do' : 'does'} not match the member's account. " \
      "Check the ID and correct the entry, or fail the call with \"Details don't match the account\"."
  end

  # The identifiers are never stored (see VerificationIdentifiers). They go
  # from the form to the decision and are then dropped.
  def identifiers_from_params
    raw = params[:identifiers]
    return nil if raw.blank?

    values = raw.permit(*VerificationIdentifiers.members).to_h.symbolize_keys
    return nil if values.values.all?(&:blank?)

    VerificationIdentifiers.from_params(values)
  end

end
