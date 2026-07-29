# frozen_string_literal: true

class MagicLinkJob < ApplicationJob
  queue_as :default

  # The raw token travels as a job argument because only its digest is stored on
  # the User::MagicLink row. That puts it in the job backend's payload for the
  # life of the job; it is deleted with the job record and dies with the link's
  # 15-minute expiry regardless.
  def perform(user, token)
    MagicLinkMailer.login_link(user, token).deliver_now
  end

end
