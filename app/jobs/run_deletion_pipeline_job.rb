# frozen_string_literal: true

# Runs the deletion pipeline for an approved request (see DeletionPipeline).
# A dormancy request is cancelled instead when the member signed in after it
# was made: any sign-in resets the dormancy clock.
class RunDeletionPipelineJob < ApplicationJob
  queue_as :default

  def perform(request_id)
    request = DeletionRequest.find_by(id: request_id)
    return if request.nil? || !(request.approved? || request.failed?)

    if request.dormancy? && request.user && request.user.last_active_at > request.requested_at
      request.cancel! if request.approved?
      return
    end

    DeletionPipeline.run!(request)
  rescue DeletionPipeline::NotRunnable => e
    Rails.logger.warn("[RunDeletionPipelineJob] #{e.message}")
  end

end
