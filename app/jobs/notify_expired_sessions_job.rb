# frozen_string_literal: true

# Sends session.expired for each session that ran out of time (see
# User::Session). A sign-out or a revocation sends the event at once, so this
# job finds only the sessions whose expiration_at passed on its own. Running
# it twice sends nothing new.
class NotifyExpiredSessionsJob < ApplicationJob
  queue_as :low

  def perform
    User::Session.expiry_not_notified.includes(:user).find_each do |session|
      session.update!(expiry_notified_at: Time.zone.now)
    end
  end

end
