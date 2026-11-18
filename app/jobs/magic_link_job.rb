# frozen_string_literal: true

class MagicLinkJob < ApplicationJob
  queue_as :default

  # Only the digest of the token is stored on the User::MagicLink row, so the
  # raw token travels as a job argument. The caller wraps it in LinkToken,
  # which stores it encrypted in the queue row. Active Job also writes job
  # arguments to the log by default, so that is turned off here.
  self.log_arguments = false

  before_enqueue { |job| LinkToken.refuse_plain!(job.arguments) }

  def perform(user, token)
    MagicLinkMailer.login_link(user, token).deliver_now
  end

end
