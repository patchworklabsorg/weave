# frozen_string_literal: true

# Sends each break-glass notice that is due (see BreakGlass). BreakGlass
# enqueues it after each decryption, and it also runs on a schedule, so a
# notice is sent even when an enqueue is lost. A member notice with a
# signed-off fraud delay waits until the delay is lifted or runs out (see
# BreakGlassNotice#held?). Running it twice sends nothing twice.
class DeliverBreakGlassNoticesJob < ApplicationJob
  queue_as :default

  def perform
    BreakGlassNotice.due.where.not(recipient_id: nil).find_each do |notice|
      notice.with_lock do
        next if notice.sent? || notice.held? || notice.due_at.future?

        mail = notice.member? ? BreakGlassMailer.member_notice(notice) : BreakGlassMailer.decrypted(notice)
        mail.deliver_now
        notice.update!(sent_at: Time.current)
        record_delay_expired(notice) if notice.delay_signed_off?
      end
    end
  end

  private

  # The delay ran out before anyone lifted it, so the notice went out.
  def record_delay_expired(notice)
    VerificationEvent.record!(notice.break_glass_record.verification, :member_notice_delay_expired,
                              break_glass_notice_id: notice.id)
  end

end
