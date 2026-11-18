# frozen_string_literal: true

# Delivers the mail of a mailer whose arguments hold a raw link token
# (MagicLinkMailer, GuardianConsentMailer). Active Job writes job arguments to
# the log by default. A token in the log would let a reader of the log use the
# link, so this job keeps its arguments out. Set it with
# `self.delivery_job = TokenMailDeliveryJob` on such a mailer.
class TokenMailDeliveryJob < ActionMailer::MailDeliveryJob
  self.log_arguments = false

end
