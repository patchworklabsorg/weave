# frozen_string_literal: true

# Break-glass access to stored ID images (see BreakGlass): ask, approve,
# deny, and open a granted image.
#
# - Ask (create): the requester's browser makes a one-time X25519 key pair,
#   keeps the private key in IndexedDB, and sends the reason and the public
#   key as JSON.
# - Approve: the browser asks for approval_options (POST: it issues a
#   challenge for this request and returns the holder's wrapped share),
#   opens the share with the hardware key, and sends the share and the
#   WebAuthn answer as JSON. The second share seals the image's data key to
#   the requester's public key. The approver does not see the image.
# - Open: the requester's browser gets the sealed data key and the encrypted
#   image (POST, JSON, no-store), once, within the handoff window. It opens
#   them with its private key and shows the image in the secure viewer.
class Identity::BreakGlassRecordsController < Identity::BaseController
  include SecureImageResponse

  RECENT_LIMIT = 20

  before_action :set_record, only: [:approval_options, :approve, :deny, :open]

  def index
    @pending = BreakGlassRecord.pending.includes(:requested_by, :approvers, :verification).order(:created_at)
    @ready = BreakGlassRecord.where(requested_by: current_user, opened_at: nil, denied_at: nil)
                             .where.not(granted_at: nil).where.not(handoff_sealed_key: nil)
                             .where(handoff_expires_at: Time.current..).order(:handoff_expires_at)
    @member_notices = BreakGlassNotice.unsent.where(recipient_kind: "member")
                                      .includes(:recipient, break_glass_decryption: :break_glass_record)
                                      .order(:due_at)
    @recent = BreakGlassRecord.where.not(id: @pending.select(:id)).includes(:requested_by)
                              .order(created_at: :desc).limit(RECENT_LIMIT)
  end

  def create
    verification = Verification.find_by_public_param!(params[:verification_id])
    result = BreakGlass.request(verification, by: current_user, reason: params[:reason],
                                              requester_public_key: params[:requester_public_key])
    if result.success?
      json_or_redirect(id: result.record.public_id, message: "Asked the key holders to approve.")
    else
      message = "Not asked: #{result.errors.values.to_sentence}."
      respond_to do |format|
        format.json { render json: { error: message }, status: :unprocessable_content }
        format.html { redirect_to identity_verification_path(verification), alert: message }
      end
    end
  end

  # The challenge for this request and the holder's wrapped share, for
  # the key custody script.
  def approval_options
    options = BreakGlass.approval_options(@record, by: current_user)
    if options
      render json: options
    else
      render json: { error: "Only a key holder who may approve this pending request, with a share of its key set, can approve it." },
             status: :unprocessable_content
    end
  end

  def approve
    credential = params[:credential].respond_to?(:to_unsafe_h) ? params[:credential].to_unsafe_h.to_hash : nil
    result = BreakGlass.approve(@record, by: current_user, credential:, share: params[:share].to_s)
    if result.success?
      message = if result.granted
                  "Approved. The request is granted. #{@record.requested_by&.full_name || 'The person who asked'} can open the image " \
                    "once, in their own browser, in the next #{VerificationSettings.break_glass_handoff_ttl.inspect}. You do not see it."
                else
                  "Approved. Your share waits, encrypted, for #{VerificationSettings.pending_share_ttl.inspect}: " \
                    "one more key holder must approve in that time."
                end
      flash[:notice] = message
      render json: { message:, granted: result.granted }
    else
      render json: { error: result.error }, status: :unprocessable_content
    end
  end

  # The sealed handoff, for the requester's browser only (see BreakGlass.open!).
  def open
    handoff = BreakGlass.open!(@record, by: current_user, ip: request.remote_ip, user_agent: request.user_agent)
    no_store_headers!
    render json: {
      sealed_key: handoff.sealed_key, ciphertext: Base64.strict_encode64(handoff.ciphertext),
      content_type: handoff.content_type, image_aad: handoff.image_aad, handoff_aad: handoff.handoff_aad,
      watermark: secure_image_watermark(@record.public_id)
    }
  rescue BreakGlass::NotPermitted => e
    render_secure_image_error(e.message, status: :unprocessable_content)
  end

  def deny
    if BreakGlass.deny(@record, by: current_user, reason: params[:reason].to_s.strip)
      redirect_to identity_break_glass_records_path, notice: "Denied."
    else
      redirect_to identity_break_glass_records_path, alert: "Only a key holder can deny a pending request, with a reason."
    end
  end

  private

  def json_or_redirect(id:, message:)
    respond_to do |format|
      format.json do
        flash[:notice] = message
        render json: { id:, message:, redirect: identity_break_glass_records_path }
      end
      format.html { redirect_to identity_break_glass_records_path, notice: message }
    end
  end

  def set_record
    @record = BreakGlassRecord.find_by_public_param!(params[:id])
  end

end
