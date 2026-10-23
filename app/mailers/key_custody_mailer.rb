# frozen_string_literal: true

# Email to the board about key custody (see KeyCustody): a ceremony, a lost
# or replaced hardware key, a compromised key set, a rotation and a failed
# unlock. The email holds the log line only, never a key or a share.
class KeyCustodyMailer < ApplicationMailer
  def event(event, board_member)
    @event = event
    @url = identity_key_custody_url

    mail(to: board_member.email, subject: env_subject("[IDP Alert] Key custody: #{event.kind.humanize.downcase}"))
  end

end
