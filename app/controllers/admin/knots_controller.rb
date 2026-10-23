# frozen_string_literal: true

# The Knot pages (see Knot, KnotChanges and docs/KYC.md).
#
# - index: the two-key requests that wait for a sign-off. The identity team,
#   board members and program patch leads can open it. Each person sees the
#   requests they can sign off, decline or withdraw.
# - show and the requests: the identity team only.
class Admin::KnotsController < Admin::BaseController
  before_action :require_identity_team, except: :index
  before_action :require_signer, only: :index
  before_action :set_knot, except: :index

  def index
    requests = KnotChangeRequest.includes(:knot, :requested_by, :verification).order(:created_at)
    @requests = requests.select do |request|
      KnotChanges.can_sign_off?(request, current_user) || request.requested_by_id == current_user.id
    end
    @blacklisted_count = Knot.where(blacklisted: true).count if current_user.identity_team
    @knot_reviews = Verification.knot_review_open.includes(:user).order(:call_scheduled_for) if current_user.identity_team
  end

  def show
    @user = @knot.user
    @hash_counts = @knot.knot_hashes.group(:kind).count
    @grants = KnotLinker.grants_received(@knot)
    @verifications = @knot.verifications.order(:created_at)
    @requests = @knot.change_requests.includes(:requested_by).order(:created_at)
  end

  def request_blacklist
    result = KnotChanges.request_blacklist(@knot, by: current_user, blacklisted: params[:blacklisted] == "1",
                                                  reason: params[:reason])
    redirect_with(result, "Request saved. A second identity team member must sign it off.")
  end

  # The identifiers are never stored. Only their hashes wait on the request.
  def request_name_change
    raw = params[:identifiers]
    values = raw.present? ? raw.permit(*VerificationIdentifiers.members).to_h.symbolize_keys : {}
    result = KnotChanges.request_name_change(@knot.user, by: current_user, evidence: params[:evidence].to_s,
                                                         note: params[:note], identifiers: VerificationIdentifiers.from_params(values))
    redirect_with(result, "Request saved. A second identity team member must sign it off.")
  end

  private

  def set_knot
    @knot = Knot.find_by_public_param!(params[:id])
  end

  def require_identity_team
    return if current_user.identity_team

    redirect_to admin_root_path, alert: "Only the identity team can open this page."
  end

  def require_signer
    return if current_user.identity_team || current_user.is_board
    return if KnotSettings.program_keys.any? { |program| KnotGrants.patch_lead?(current_user, program) }

    redirect_to admin_root_path, alert: "Only the identity team, the board and patch leads can open this page."
  end

  def redirect_with(result, notice)
    if result.success?
      redirect_to admin_knot_path(@knot), notice:
    else
      redirect_to admin_knot_path(@knot), alert: "Not saved: #{error_text(result.errors)}."
    end
  end

  def error_text(errors) = errors.map { |key, message| key == :base ? message : "#{key.to_s.humanize} #{message}" }.join(". ")

end
