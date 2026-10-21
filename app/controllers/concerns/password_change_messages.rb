# frozen_string_literal: true

# The messages a password change can show, shared by the change-password page
# and the expired-password page. AD policy refusals (0000052D) get their own
# message, so the person knows to choose a different password.
module PasswordChangeMessages
  extend ActiveSupport::Concern

  PASSWORD_CHANGE_MESSAGES = {
    blank: "Enter a new password.",
    mismatch: "The new password and the confirmation are not the same.",
    current_missing: "Enter your current password.",
    policy_rejected: "The new password does not meet the Patchwork password policy. Use a longer password that you have not used before, and that does not contain your name.",
    invalid_current_password: "Your current password is not correct.",
    throttled: "Too many failed attempts. Wait 15 minutes, then try again.",
    failed: "Weave could not change your password now. Try again later, or contact an administrator."
  }.freeze

  private

  # Returns the message key for a bad form, or nil when the form is complete.
  def new_password_problem(password, confirmation)
    return :blank if password.blank?

    :mismatch unless ActiveSupport::SecurityUtils.secure_compare(password, confirmation)
  end

  def password_change_message(status)
    PASSWORD_CHANGE_MESSAGES.fetch(status) { PASSWORD_CHANGE_MESSAGES[:failed] }
  end

end
