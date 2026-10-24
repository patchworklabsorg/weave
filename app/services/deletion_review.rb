# frozen_string_literal: true

# Deletion requests and their human review (proposal section 06,
# "Self-service deletion").
#
# - The member asks (request!), or DormancyJob asks for a dormant account.
# - A human on the identity team reviews every request. It is an
#   authenticity check (is this really the member, or really a dormant
#   account?), not a judgment call. The review is due review_sla_days after
#   the request, and the page shows the due date.
# - On approval, RunDeletionPipelineJob runs DeletionPipeline.
# - A rejection needs a written reason: the authenticity check failed.
module DeletionReview
  Result = Data.define(:request, :errors) do
    def success? = errors.empty?
  end

  class << self
    def request!(user, source: "member")
      request = DeletionRequest.new(user:, source:)
      return Result.new(request:, errors: request.errors.to_hash) unless request.save

      DataHandlingMailer.deletion_requested(request).deliver_later if source == "member"
      User.identity_leads.find_each { |lead| DataHandlingMailer.review_needed(request, lead).deliver_later }
      Result.new(request:, errors: {})
    end

    # The member takes the request back while it waits for review.
    def cancel!(request)
      return false unless request.pending_review? || request.approved?

      request.cancel!
      true
    end

    def approve(request, by:, note:)
      errors = review_errors(request, by, note)
      return Result.new(request:, errors:) if errors.any?

      request.with_lock do
        return Result.new(request:, errors: { base: "This request is no longer waiting for review." }) unless request.pending_review?

        request.update!(reviewed_by: by, reviewed_at: Time.current, review_note: note.to_s.strip)
        request.approve!
      end
      RunDeletionPipelineJob.perform_later(request.id)
      Result.new(request:, errors: {})
    end

    def reject(request, by:, note:)
      errors = review_errors(request, by, note)
      return Result.new(request:, errors:) if errors.any?

      request.with_lock do
        return Result.new(request:, errors: { base: "This request is no longer waiting for review." }) unless request.pending_review?

        request.update!(reviewed_by: by, reviewed_at: Time.current, review_note: note.to_s.strip)
        request.reject!
      end
      DataHandlingMailer.deletion_rejected(request).deliver_later if request.source == "member" && request.receipt_email.present?
      Result.new(request:, errors: {})
    end

    # Runs the pipeline again after a failed run.
    def retry!(request, by:)
      return false unless request.failed? && can_review?(by, request)

      RunDeletionPipelineJob.perform_later(request.id)
      true
    end

    def can_review?(by, request)
      return false unless by&.identity_team && by.admin?
      return false if request.user_id && by.id == request.user_id

      request.user.nil? || UserAdminPermissions.new(by, request.user).manage?
    end

    private

    def review_errors(request, by, note)
      return { base: "Only the identity team can review a deletion request, and never their own or a user at or above their access level." } unless can_review?(by, request)
      return { review_note: "Say how you checked the request." } if note.to_s.strip.blank?

      {}
    end

  end
end
