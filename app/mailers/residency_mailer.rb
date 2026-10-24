# frozen_string_literal: true

# Email for the US residency check (see ResidencyFlow). The text comes from
# config/locales/residency.en.yml.
class ResidencyMailer < ApplicationMailer
  # A document review is decided or sent back.
  def status_changed(check)
    key = if check.needs_resubmission? then "needs_resubmission"
          elsif check.us_resident then "decided_yes"
          else "decided_no"
          end
    deliver_status(check, key)
  end

  # The member's address moved, so a yes result ended.
  def ended(check) = deliver_status(check, "ended")

  # A yes result ends soon (see RenewResidencyChecksJob).
  def renewal_due(check) = deliver_status(check, "renewal_due")

  private

  def deliver_status(check, key)
    @user = check.user
    @key = key
    @status_url = verification_url
    @body = t("residency.mailer.#{key}.body",
              first_name: @user.first_name, state: check.us_state_name.to_s, note: check.resubmission_note.to_s,
              date: check.expires_at&.to_date&.to_fs(:long).to_s,
              days: VerificationSettings.purge_image_after_pass.in_days.to_i)

    mail(to: @user.email, subject: env_subject(t("residency.mailer.#{key}.subject")), template_name: "status_changed")
  end

end
