# frozen_string_literal: true

# Deletes each key custody share that waited longer than
# pending_share_minutes (see KeyCustody::PendingShares). take and holder_ids
# already ignore an expired share, so this job only removes the rows.
#
# It also deletes each sealed break-glass handoff that the requester did not
# open in time (BreakGlass.sweep_expired_handoffs!), and WebAuthn challenges that expired more than a day ago (see
# KeyCustodyChallenge). A challenge holds no secret.
class SweepPendingSharesJob < ApplicationJob
  queue_as :default

  def perform
    KeyCustody::PendingShares.sweep!
    BreakGlass.sweep_expired_handoffs!
    KeyCustodyChallenge.where(expires_at: ...1.day.ago).delete_all
  end

end
