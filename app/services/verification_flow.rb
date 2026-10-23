# frozen_string_literal: true

# The steps of identity verification, with what each one sets off (see
# Verification and docs/KYC.md).
#
#   member submits an ID -> identity team pre-review -> "Document OK"
#     -> call time agreed by email or Slack -> live call -> decision
#
# - A document problem at pre-review goes back to the member with a note. The
#   member submits a new attempt at once.
# - A failed call starts a cooldown. Then the member runs the full flow again,
#   and a different verifier must run the call: nobody who failed the member
#   before can verify them again.
# - After a configured number of failed calls, the attempt goes to the
#   identity team lead instead. The lead allows one more round or closes the
#   case (ineligible).
#
# Each step adds a VerificationEvent. Nobody verifies their own account. A
# key holder may verify, but the lead verifier on a member's calls can't
# approve break-glass access for that member (see BreakGlass.may_approve?).
module VerificationFlow
  Result = Data.define(:verification, :errors) do
    def success? = errors.empty?
  end

  OUTCOMES = %w[verified failed].freeze

  class << self
    # Why the user can't submit an attempt now, or nil when they can.
    def submission_blocker(user)
      return :under_minimum_age if user.under_minimum_age?
      return :no_birthday if user.birthday.nil?

      latest = user.latest_verification
      return nil if latest.nil?
      return :verified if latest.standing_pass?
      return :ineligible if latest.ineligible?
      return :in_progress if latest.in_progress?
      return :escalated if latest.escalation_open?
      return :cooldown if latest.failed? && latest.retry_available_at.future?

      nil
    end

    # The member submits an ID image ahead of the call.
    def submit(user, document:, document_type:, verification_method: "document_call")
      verification = Verification.new(user:, verification_method:, document_type: document_type.presence)
      if verification.digital_id_call? && !DigitalIdProvider.available?
        return failure(verification, verification_method: I18n.t("verification.errors.digital_id_unavailable"))
      end

      # The conversion runs before anything is stored, so only the converted
      # image is ever kept.
      attachable = nil
      if document.present? && verification.document_call?
        begin
          attachable = converted_attachable(document)
        rescue IdDocumentConverter::Refused => e
          Rails.logger.info("ID upload refused: #{e.message}")
          return failure(verification, id_document: I18n.t("verification.errors.document_unsupported"))
        end
      end

      # A row lock on the user stops two submissions from racing. (Not
      # User#with_lock: User#lock! locks the account.)
      Verification.transaction do
        User.lock.find(user.id)
        blocker = submission_blocker(user)
        return failure(verification, base: I18n.t("verification.blockers.#{blocker}")) if blocker

        verification.previous_attempt = user.latest_verification
        verification.id_document.attach(attachable) if attachable
        verification.save || raise(ActiveRecord::Rollback)
        VerificationEvent.record!(verification, :submitted, actor: user, verification_method:,
                                                            document_type: verification.document_type)
      end
      return failure(verification, verification.errors.to_hash.transform_values(&:first)) unless verification.persisted?

      Result.new(verification:, errors: {})
    end

    # An identity team member takes the attempt for pre-review. Only they can
    # see the image while it is in pre-review.
    def start_pre_review(verification, by:)
      return false unless identity_member?(by, verification)

      verification.with_lock do
        return false unless verification.submitted?

        verification.assign_attributes(pre_reviewer: by, pre_review_started_at: Time.current)
        verification.start_pre_review!
        VerificationEvent.record!(verification, :pre_review_started, actor: by)
      end
      true
    end

    # Another identity team member takes over a pre-review (for example when
    # the pre-reviewer is away). The hand-over is logged with the old and the
    # new pre-reviewer. From then on only the new pre-reviewer can see the
    # image and mark the document OK.
    def take_over_pre_review(verification, by:)
      return false unless identity_member?(by, verification)

      verification.with_lock do
        return false unless verification.pre_review? && verification.pre_reviewer_id != by.id

        from_id = verification.pre_reviewer_id
        verification.update!(pre_reviewer: by)
        VerificationEvent.record!(verification, :pre_review_taken_over, actor: by, from_pre_reviewer_id: from_id,
                                                                        to_pre_reviewer_id: by.id)
      end
      true
    end

    # The pre-reviewer opens the ID image. The view is logged before the image
    # is decrypted. Returns the image bytes, or nil when not permitted. Any
    # other decryption needs a break-glass request (see BreakGlass).
    def pre_review_document(verification, by:)
      return nil unless verification.pre_review? && verification.pre_reviewer_id == by&.id && by.identity_team
      return nil unless verification.document_stored?

      VerificationEvent.record!(verification, :document_viewed, actor: by, context: "pre_review")
      verification.id_document.download
    end

    # A document problem: the member submits again, with this note.
    def reject_document(verification, by:, note:)
      return false unless identity_member?(by, verification) && note.present?

      verification.with_lock do
        return false unless verification.pre_review?

        verification.assign_attributes(resubmission_note: note, pre_reviewed_at: Time.current)
        verification.reject_document!
        VerificationEvent.record!(verification, :document_rejected, actor: by, note:)
      end
      notify_member(verification)
      true
    end

    # "Document OK": the pre-reviewer ends pre-review. The attempt waits for a
    # call time (awaiting_call). The verifier agrees the time with the member
    # by email or Slack, and then records it (schedule_call).
    def approve_document(verification, by:)
      return false unless identity_member?(by, verification) && verification.pre_reviewer_id == by.id

      verification.with_lock do
        return false unless verification.pre_review?

        verification.assign_attributes(pre_reviewed_at: Time.current)
        verification.approve_document!
        VerificationEvent.record!(verification, :document_approved, actor: by)
      end
      notify_member(verification)
      true
    end

    # Records the call time that the verifier agreed with the member. Also
    # moves a call. It does not touch the image.
    def schedule_call(verification, by:, at:)
      return false unless identity_member?(by, verification) && at.present? && at.future?

      verification.with_lock do
        return false unless verification.awaiting_call? || verification.call_scheduled?

        verification.assign_attributes(call_scheduled_for: at, call_scheduled_by: by)
        verification.schedule_call!
        VerificationEvent.record!(verification, :call_scheduled, actor: by, at: at.iso8601)
      end
      notify_member(verification)
      true
    end

    # The verifier records the outcome of the live call. by is the verifier.
    #
    # age_consistent and region_consistent are the yes/no attestation that
    # the self-reported age and region do not contradict the ID. No value from
    # the ID is written down, and gender is never checked.
    #
    # identifiers (a VerificationIdentifiers) go to the subscribers of
    # VerificationIdentifiers::EVENT and are then dropped. A pass of a
    # document call needs them.
    def decide(verification, by:, outcome:, reason:, age_consistent:, region_consistent:,
               second_verifier: nil, guardian_attended: false, identifiers: nil)
      user = verification.user
      errors = decision_errors(verification, user, by:, outcome:, reason:, age_consistent:, region_consistent:,
                                                   second_verifier:, guardian_attended:, identifiers:)
      return failure(verification, errors) if errors.any?

      escalated = false
      Verification.transaction do
        verification.lock!
        unless verification.call_scheduled?
          return failure(verification, base: "The call outcome is already recorded.")
        end

        verification.assign_attributes(
          verifier: by, second_verifier:, guardian_attended:,
          guardian_consent: (user.guardian_consents.granted.order(:granted_at).last if guardian_attended || user.minor?),
          age_consistent:, region_consistent:, decision_reason: reason, decided_at: Time.current
        )
        outcome == "verified" ? verification.mark_verified! : verification.mark_failed!
        VerificationEvent.record!(
          verification, :decided,
          actor: by, outcome:, reason:, verification_method: verification.verification_method,
          document_type: verification.document_type,
          attendees: {
            member_id: user.id, verifier_id: by.id, second_verifier_id: second_verifier&.id,
            guardian_attended:, guardian_consent_id: verification.guardian_consent_id
          },
          age_consistent:, region_consistent:
        )
        if identifiers
          ActiveSupport::Notifications.instrument(VerificationIdentifiers::EVENT, verification:, outcome:, identifiers:)
        end
        escalated = escalate_if_due(verification)
      end

      notify_member(verification)
      notify_leads_of_escalation(verification) if escalated
      Result.new(verification:, errors: {})
    end

    # The identity team lead decides an escalated case: one more round
    # ("retry_allowed", after the cooldown) or a closed case ("ineligible").
    def resolve_escalation(verification, by:, resolution:, note:)
      return false unless by&.identity_lead && identity_member?(by, verification)
      return false unless Verification::ESCALATION_RESOLUTIONS.include?(resolution) && note.present?

      verification.with_lock do
        return false unless verification.escalation_open?

        verification.update!(escalation_resolution: resolution, escalation_note: note,
                             escalation_resolved_at: Time.current, escalation_resolved_by: by)
        VerificationEvent.record!(verification, :escalation_resolved, actor: by, resolution:, note:)
      end
      notify_member(verification)
      true
    end

    # Ends the member's standing pass after a trigger: a birthday change, a
    # legal name change or a blacklist review. A pass has no time limit, so
    # these are the only ways it ends. The attempt stays verified (the call did
    # pass), the reason goes on the attempt and in the audit record, the
    # member's status goes back to needs_submission, and the member is told.
    # Returns true when it ended a pass.
    def require_reverification(user, reason:, actor: nil)
      raise ArgumentError, "unknown reverification reason #{reason}" unless Verification::REVERIFICATION_REASONS.include?(reason.to_s)

      verification = user&.latest_verification
      return false unless verification&.standing_pass?

      verification.with_lock do
        return false unless verification.standing_pass?

        verification.update!(reverification_required_at: Time.current, reverification_reason: reason.to_s)
        VerificationEvent.record!(verification, :reverification_required, actor:, reason: reason.to_s)
      end
      notify_member(verification)
      true
    end

    # Everyone who failed the member before, as the verifier or the second
    # verifier. None of them can verify the member again.
    def excluded_verifier_ids(user)
      return [] if user.nil?

      user.verifications.failed.pluck(:verifier_id, :second_verifier_id).flatten.compact.uniq
    end

    # Failed calls since the lead last allowed a retry.
    def failed_calls_since_reset(user)
      reset_at = user.verifications.where(escalation_resolution: "retry_allowed").maximum(:escalation_resolved_at)
      scope = user.verifications.failed
      scope = scope.where(decided_at: reset_at..) if reset_at
      scope.count
    end

    private

    def identity_member?(by, verification) = by&.identity_team && by.id != verification.user_id

    def decision_errors(verification, user, by:, outcome:, reason:, age_consistent:, region_consistent:,
                        second_verifier:, guardian_attended:, identifiers:)
      errors = {}
      return { base: "The member's account no longer exists." } if user.nil?
      return { base: "Only an identity team member who is not the member can record the outcome." } unless identity_member?(by, verification)
      return { base: "Schedule the call before you record its outcome." } unless verification.call_scheduled?

      excluded = excluded_verifier_ids(user)
      errors[:verifier] = "You failed this member before. A different verifier must run this call." if excluded.include?(by.id)
      if second_verifier
        if !second_verifier.identity_team || second_verifier == by || second_verifier.id == user.id
          errors[:second_verifier] = "must be another identity team member"
        elsif excluded.include?(second_verifier.id)
          errors[:second_verifier] = "failed this member before, so they can't verify them again"
        end
      end
      errors[:outcome] = "must be verified or failed" unless OUTCOMES.include?(outcome)
      errors[:reason] = "is required: write what you checked and why you decided" if reason.blank?
      errors[:age_consistent] = "must be yes or no" if age_consistent.nil?
      errors[:region_consistent] = "must be yes or no" if region_consistent.nil?
      if guardian_attended && !user.guardian_consent_granted?
        errors[:guardian_attended] = "needs a granted guardian consent on file"
      end
      if outcome == "verified"
        errors.merge!(pass_errors(verification, user, age_consistent:, region_consistent:, guardian_attended:,
                                                      identifiers:))
      end
      if identifiers && outcome != "verified"
        identifiers.errors.each { |key, message| errors[:"identifiers_#{key}"] = message }
      end
      errors
    end

    # A pass needs a consistent age and region, a guardian's consent and a
    # guardian on the call for a minor, and the identifiers from a document.
    def pass_errors(verification, user, age_consistent:, region_consistent:, guardian_attended:, identifiers:)
      errors = {}
      errors[:age_consistent] = "is no: an age mismatch can't pass. Fail the call, or ask the member to fix their birthday first." if age_consistent == false
      errors[:region_consistent] = "is no: a region mismatch can't pass" if region_consistent == false
      errors[:base] = "A member under 18 needs a granted guardian consent before they can pass." if user.guardian_consent_missing?
      if user.minor? && !guardian_attended
        errors[:guardian_attended] = "is required: a parent or guardian must attend the call of a member under 18"
      end
      if verification.document_call?
        if identifiers.nil?
          errors[:identifiers] = "are required for a pass"
        else
          identifiers.errors.each { |key, message| errors[:"identifiers_#{key}"] = message }
        end
      end
      errors
    end

    # Marks the attempt for the lead when the member has failed too many
    # calls. Returns true when it did.
    def escalate_if_due(verification)
      return false unless verification.failed?

      failed_calls = failed_calls_since_reset(verification.user)
      return false if failed_calls < VerificationSettings.failed_calls_before_escalation

      verification.update!(escalated_at: Time.current)
      VerificationEvent.record!(verification, :escalated, failed_calls:)
      true
    end

    def notify_member(verification)
      return if verification.user.nil?

      VerificationMailer.status_changed(verification).deliver_later
    end

    def notify_leads_of_escalation(verification)
      User.identity_leads.where.not(id: verification.user_id).find_each do |lead|
        VerificationMailer.escalated(verification, lead).deliver_later
      end
    end

    def failure(verification, errors) = Result.new(verification:, errors:)

    # The upload, converted in memory (IdDocumentConverter): HEIC to JPEG,
    # the first page of a PDF to PNG, no metadata. The file name of an upload
    # often holds the member's name (for example "jane_doe_passport.jpg"),
    # and Active Storage keeps the file name in plain text, so the image is
    # stored as "id_document" plus the extension. Raises
    # IdDocumentConverter::Refused.
    def converted_attachable(document)
      if document.respond_to?(:size) && document.size.to_i > VerificationSettings.max_image_size
        raise IdDocumentConverter::Refused, "The file is too large."
      end

      converted = IdDocumentConverter.convert(document)
      { io: converted.io, filename: converted.filename, content_type: converted.content_type, identify: false }
    end

  end
end
