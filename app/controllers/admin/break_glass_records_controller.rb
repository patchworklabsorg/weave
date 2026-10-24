# frozen_string_literal: true

# Break-glass access to stored ID images (see BreakGlass): ask, approve or
# deny, and open the image under a granted request.
class Admin::BreakGlassRecordsController < Admin::BaseController
  include IdentityTeamAccess
  include SecureImageResponse

  RECENT_LIMIT = 20

  before_action :set_record, only: [:approve, :deny, :image]

  def index
    @pending = BreakGlassRecord.pending.includes(:requested_by, :approvers, :verification).order(:created_at)
    @mine = BreakGlassRecord.where(requested_by: current_user).where.not(granted_at: nil).where(denied_at: nil)
                            .where(expires_at: Time.current..).order(:expires_at)
    @member_notices = BreakGlassNotice.unsent.where(recipient_kind: "member")
                                      .includes(:recipient, break_glass_decryption: :break_glass_record)
                                      .order(:due_at)
    @recent = BreakGlassRecord.where.not(id: @pending.select(:id)).includes(:requested_by)
                              .order(created_at: :desc).limit(RECENT_LIMIT)
  end

  def create
    verification = Verification.find_by_public_param!(params[:verification_id])
    result = BreakGlass.request(verification, by: current_user, reason: params[:reason])
    if result.success?
      redirect_to admin_break_glass_records_path, notice: "Asked the key holders to approve."
    else
      redirect_to admin_verification_path(verification), alert: "Not asked: #{result.errors.values.to_sentence}."
    end
  end

  def approve
    if BreakGlass.approve(@record, by: current_user)
      redirect_to admin_break_glass_records_path, notice: @record.reload.granted? ? "Approved. The request is granted." : "Approved. One more key holder must approve."
    else
      redirect_to admin_break_glass_records_path, alert: "Only a key holder who has not approved yet can approve a pending request."
    end
  end

  def deny
    if BreakGlass.deny(@record, by: current_user, reason: params[:reason].to_s.strip)
      redirect_to admin_break_glass_records_path, notice: "Denied."
    else
      redirect_to admin_break_glass_records_path, alert: "Only a key holder can deny a pending request, with a reason."
    end
  end

  # Decrypts the image for the secure viewer. BreakGlass.decrypt! commits
  # the log and the notices first.
  def image
    decrypted = BreakGlass.decrypt!(@record, viewer: current_user, ip: request.remote_ip, user_agent: request.user_agent)
    render_secure_image(data: decrypted.data, content_type: decrypted.content_type, subject_id: @record.public_id)
  rescue BreakGlass::NotPermitted => e
    render_secure_image_error(e.message)
  end

  private

  def set_record
    @record = BreakGlassRecord.find_by_public_param!(params[:id])
  end

end
