# frozen_string_literal: true

# Email for identity verification (see VerificationFlow). The member hears
# about each step. The identity team lead hears about each escalation.
class VerificationMailer < ApplicationMailer
  # One email for each step the member must know about. The text comes from
  # config/locales/verification.en.yml, by status.
  def status_changed(verification)
    @verification = verification
    @user = verification.user
    @key = mail_key(verification)
    @status_url = verification_url
    @data_page_url = Weave.data_page_url
    @body = t("verification.mailer.#{@key}.body",
              first_name: @user.first_name,
              note: verification.resubmission_note.to_s,
              call_time: verification.call_scheduled_for&.utc&.strftime("%B %-d, %Y at %H:%M UTC").to_s,
              retry_date: verification.retry_available_at&.to_date&.to_fs(:long).to_s,
              days: VerificationSettings.purge_image_after_pass.in_days.to_i,
              reason: reverification_reason_text(verification))

    mail(to: @user.email, subject: env_subject(t("verification.mailer.#{@key}.subject")))
  end

  def escalated(verification, lead)
    @verification = verification
    @user = verification.user
    @failed_calls = VerificationFlow.failed_calls_since_reset(@user)
    @admin_url = admin_verification_url(verification)

    mail(to: lead.email, subject: env_subject("[IDP Alert] Verification escalated for #{@user.p_id}"))
  end

  private

  def reverification_reason_text(verification)
    return "" unless verification.reverification_required?

    t("verification.reverification_reasons.#{verification.reverification_reason}")
  end

  def mail_key(verification)
    if verification.reverification_required? then "reverification_required"
    elsif verification.escalation_resolution.present? then "escalation_#{verification.escalation_resolution}"
    elsif verification.escalation_open? then "escalated"
    else
      verification.status
    end
  end

end
