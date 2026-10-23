# frozen_string_literal: true

# Builds a member's data export and emails them the link (see Takeout).
class BuildTakeoutJob < ApplicationJob
  queue_as :default

  def perform(takeout_request_id)
    request = TakeoutRequest.find_by(id: takeout_request_id)
    Takeout.deliver!(request) if request&.pending?
  end

end
