# frozen_string_literal: true

# Email for break-glass access to stored ID images (see BreakGlass): the
# approval request, the notice ladder and the board report.
class BreakGlassMailer < ApplicationMailer
  def approval_needed(record, holder)
    @record = record
    @admin_url = identity_break_glass_records_url

    mail(to: holder.email, subject: env_subject("[IDP Alert] Break-glass approval needed (#{record.public_id})"))
  end

  # To the other key holder and the identity team lead, at once.
  def decrypted(notice)
    @notice = notice
    @decryption = notice.break_glass_decryption
    @record = notice.break_glass_record
    @admin_url = identity_break_glass_records_url

    mail(to: notice.recipient.email, subject: env_subject("[IDP Alert] A stored ID image was decrypted (#{@record.public_id})"))
  end

  # To the member, after the notice window.
  def member_notice(notice)
    @notice = notice
    @user = notice.recipient
    @decryption = notice.break_glass_decryption
    @record = notice.break_glass_record
    @data_page_url = Weave.data_page_url

    mail(to: @user.email, subject: env_subject(t("verification.break_glass_notice.subject")))
  end

  def notice_delayed(notice, lead)
    @notice = notice
    @record = notice.break_glass_record
    @admin_url = identity_break_glass_records_url

    mail(to: lead.email, subject: env_subject("[IDP Alert] A member notice was delayed (#{@record.public_id})"))
  end

  def board_report(member, month)
    @report = BreakGlassReport.new(Date.iso8601(month))
    @report_url = admin_break_glass_report_url(month: @report.month.iso8601)

    mail(to: member.email, subject: env_subject("Weave break-glass report for #{@report.month.strftime('%B %Y')}"))
  end

end
