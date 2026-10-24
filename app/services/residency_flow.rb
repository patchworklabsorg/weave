# frozen_string_literal: true

# The US residency check (see ResidencyCheck and docs/KYC.md). OSPool lets
# only US residents use its capacity, so every verified member gets a result.
# Residency is where the member lives, not citizenship: never ask about
# citizenship.
#
# - On the identity call: a US driver's license, learner's permit or state ID
#   with a current US address is enough. A member without one (common under
#   18) uploads a proof document with the ID: a current US school enrollment
#   record, the guardian's US state ID, or the guardian's ID and a proof of
#   address. The verifier records the result at the decision (record_call!).
# - Without a call: a member who already passed identity verification
#   uploads a proof document (submit_document), and a verifier decides it in
#   pre-review (decide_review). A member who does not live in the US says so
#   (declare_non_resident) and needs no document.
#
# A yes result stands for VerificationSettings.residency_valid_for, or until
# the state or country of the member's shipping address changes
# (address_changed!). RenewResidencyChecksJob reminds the member before it
# ends.
module ResidencyFlow
  Result = VerificationFlow::Result

  STATUSES = %w[us_resident not_us_resident pending needs_check].freeze

  class << self
    # us_resident, not_us_resident, pending (a check is open) or needs_check.
    def status(user)
      return "pending" if open_check(user)

      check = current_check(user)
      return "needs_check" if check.nil?

      check.us_resident ? "us_resident" : "not_us_resident"
    end

    # true or false while a result stands, nil otherwise.
    def us_resident?(user)
      check = current_check(user)
      check&.us_resident
    end

    # The latest decided check, when it still stands.
    def current_check(user)
      return nil if user.nil?

      check = user.residency_checks.where(status: "decided").where.not(us_resident: nil)
                  .order(:decided_at, :id).last
      check if check&.standing?
    end

    # An open check: a document review, or a check on an identity attempt
    # that is still open.
    def open_check(user)
      return nil if user.nil?

      user.residency_checks.open.order(:created_at, :id).find do |check|
        check.document_review? || check.verification&.in_progress?
      end
    end

    # Why the member can't ask for a check without a call now, or nil.
    def submission_blocker(user)
      return :identity_needed unless user.identity_verified?
      return :in_progress if open_check(user)

      check = current_check(user)
      return :standing if check&.us_resident && check.expires_at > VerificationSettings.residency_renewal_reminder.from_now

      nil
    end

    # The member uploads a proof document for a check without a call.
    def submit_document(user, document:, evidence_type:)
      check = ResidencyCheck.new(user:, source: "document_review", evidence_type: evidence_type.to_s)
      unless ResidencyCheck::UPLOAD_EVIDENCE.include?(check.evidence_type) || check.evidence_type == "id_document"
        return failure(check, evidence_type: I18n.t("residency.errors.evidence_type"))
      end
      return failure(check, document: I18n.t("residency.errors.document_missing")) if document.blank?

      attachable = converted(document)
      return failure(check, document: I18n.t("verification.errors.document_unsupported")) if attachable.nil?

      ResidencyCheck.transaction do
        User.lock.find(user.id)
        blocker = submission_blocker(user)
        return failure(check, base: blocker_message(blocker)) if blocker

        check.document.attach(attachable)
        check.save || raise(ActiveRecord::Rollback)
      end
      return failure(check, check.errors.to_hash.transform_values(&:first)) unless check.persisted?

      Result.new(verification: check, errors: {})
    end

    # The member says they do not live in the US (for example after a move).
    # This is a no result at once, with no document, and it replaces a yes. A
    # later check can change it.
    def declare_non_resident(user)
      check = nil
      ResidencyCheck.transaction do
        User.lock.find(user.id)
        blocker = submission_blocker(user)
        return failure(ResidencyCheck.new, base: blocker_message(blocker)) if blocker && blocker != :standing

        end_current!(user, reason: "replaced")
        check = ResidencyCheck.create!(user:, source: "document_review", evidence_type: ResidencyCheck::MEMBER_STATEMENT,
                                       status: "decided", us_resident: false, decided_at: Time.current)
      end
      Result.new(verification: check, errors: {})
    end

    # The member's proof document goes with an identity submission (see
    # VerificationFlow.submit). Call it inside the submission transaction.
    def attach_to_submission!(verification, document:, evidence_type:)
      check = ResidencyCheck.new(user: verification.user, verification:, source: "identity_call",
                                 evidence_type: evidence_type.to_s)
      raise ArgumentError, "unknown evidence type" unless ResidencyCheck::UPLOAD_EVIDENCE.include?(check.evidence_type)

      attachable = converted(document)
      raise IdDocumentConverter::Refused, "The residency document can't be read." if attachable.nil?

      check.document.attach(attachable)
      check.save!
      check
    end

    # The check that goes with an identity attempt, if any.
    def check_for(verification) = ResidencyCheck.where(verification:).order(:id).last

    # A verifier takes a document review for pre-review.
    def start_pre_review(check, by:)
      return false unless reviewer?(by, check) && check.document_review?

      check.with_lock do
        return false unless check.submitted?

        check.update!(status: "pre_review", pre_reviewer: by, pre_review_started_at: Time.current)
      end
      true
    end

    # The pre-reviewer opens the proof document: of a document review in
    # pre-review, or of an identity attempt that they pre-review. Every view
    # is logged. Returns the bytes, or nil when not permitted.
    def pre_review_document(check, by:)
      return nil unless by&.identity_team && check.document.attached? && check.document_purged_at.nil?

      if check.identity_call?
        verification = check.verification
        return nil unless verification&.pre_review? && verification.pre_reviewer_id == by.id

        VerificationEvent.record!(verification, :document_viewed, actor: by, context: "residency_pre_review")
      else
        return nil unless check.pre_review? && check.pre_reviewer_id == by.id

        # The view is logged as a PaperTrail version of the check.
        PaperTrail.request(whodunnit: by.id.to_s) { check.touch } # rubocop:disable Rails/SkipsModelValidations
      end
      ResidencyDocumentVault.pre_review_read(check)
    end

    # A document problem: the member uploads again, with this note. The
    # document is sealed, like an ID image.
    def reject_document(check, by:, note:)
      return false unless reviewer?(by, check) && check.document_review? && note.present?

      check.with_lock do
        return false unless check.pre_review? && check.pre_reviewer_id == by.id

        check.update!(status: "needs_resubmission", resubmission_note: note, pre_reviewed_at: Time.current)
        ResidencyDocumentVault.seal!(check)
      end
      notify(check)
      true
    rescue KeyCustody::NotSetUp
      check.reload
      false
    end

    # The pre-reviewer decides a document review: yes with the US state, or
    # no. The verifier may correct the evidence type to what the document is.
    def decide_review(check, by:, us_resident:, us_state:, evidence_type:)
      errors = result_errors(us_resident:, us_state:, evidence_type:)
      errors[:base] = "Only the pre-reviewer can decide this check." unless reviewer?(by, check) && check.pre_reviewer_id == by.id
      return failure(check, errors) if errors.any?

      check.with_lock do
        return failure(check, base: "This check is not in pre-review.") unless check.pre_review?

        end_current!(check.user, reason: "replaced")
        check.update!(status: "decided", us_resident:, us_state: (us_state if us_resident),
                      evidence_type: us_resident ? evidence_type : (evidence_type.presence || "none"),
                      decided_by: by, decided_at: Time.current, pre_reviewed_at: Time.current)
        ResidencyDocumentVault.seal!(check)
      end
      notify(check)
      Result.new(verification: check, errors: {})
    rescue KeyCustody::NotSetUp
      check.reload
      failure(check, base: KeyCustody.warning_for_pre_review || "Key custody is not set up.")
    end

    # The errors in the residency part of an identity call outcome, for a
    # pass. Evidence other than the ID itself needs the proof document that
    # the member uploaded with the ID.
    def call_errors(verification, us_resident:, us_state:, evidence_type:)
      errors = result_errors(us_resident:, us_state:, evidence_type:)
      if us_resident && ResidencyCheck::UPLOAD_EVIDENCE.include?(evidence_type) && check_for(verification)&.document_stored? != true
        errors[:residency_evidence] = "needs the proof document the member uploaded with the ID"
      end
      errors
    end

    # The verifier records the residency result of an identity call. Call it
    # inside the decision transaction. A fail records no result.
    def record_call!(verification, by:, outcome:, us_resident:, us_state:, evidence_type:)
      check = check_for(verification)
      if outcome != "verified"
        close_without_result!(check) if check&.open?
        return check
      end

      end_current!(verification.user, reason: "replaced")
      check ||= ResidencyCheck.new(user: verification.user, verification:, source: "identity_call")
      check.update!(status: "decided", us_resident:, us_state: (us_state if us_resident),
                    evidence_type: us_resident ? evidence_type : "none",
                    decided_by: by, decided_at: Time.current)
      check
    end

    # Pre-review of an identity attempt ended: the proof document is sealed
    # with the ID image. A sent-back attempt sends the document back too.
    def identity_pre_review_ended!(verification, note: nil)
      check = check_for(verification)
      return if check.nil? || !check.open?

      if note
        check.update!(status: "needs_resubmission", resubmission_note: note, pre_reviewed_at: Time.current)
      else
        check.update!(status: "pre_review", pre_reviewer: verification.pre_reviewer, pre_reviewed_at: Time.current)
      end
      ResidencyDocumentVault.seal!(check)
    end

    # The state or country of the member's shipping address changed: a yes
    # result stops standing, and the member is asked for a new check.
    def address_changed!(user)
      check = current_check(user)
      return false unless check&.us_resident

      check.update!(ended_at: Time.current, end_reason: "address_changed")
      ResidencyMailer.ended(check).deliver_later
      true
    end

    private

    def reviewer?(by, check) = by&.identity_team && by.id != check.user_id

    def blocker_message(blocker)
      I18n.t("residency.blockers.#{blocker}", days: VerificationSettings.residency_renewal_reminder.in_days.to_i)
    end

    def result_errors(us_resident:, us_state:, evidence_type:)
      errors = {}
      if us_resident.nil?
        errors[:us_resident] = "must be yes or no"
      elsif us_resident
        errors[:us_state] = "must be a US state" unless ResidencyCheck::US_STATES.key?(us_state.to_s)
        unless (ResidencyCheck::UPLOAD_EVIDENCE + ["id_document"]).include?(evidence_type.to_s)
          errors[:residency_evidence] = "must say what shows US residency"
        end
      end
      errors
    end

    # A standing result ends when a newer one replaces it.
    def end_current!(user, reason:)
      check = current_check(user)
      check&.update!(ended_at: Time.current, end_reason: reason)
    end

    # The identity call failed: its proof document gives no result.
    def close_without_result!(check)
      check.update!(status: "needs_resubmission", resubmission_note: "The identity call did not pass.",
                    pre_reviewed_at: check.pre_reviewed_at || Time.current)
    end

    def notify(check)
      return if check.user.nil?

      ResidencyMailer.status_changed(check).deliver_later
    end

    def converted(document)
      return nil if document.respond_to?(:size) && document.size.to_i > VerificationSettings.max_image_size

      converted = IdDocumentConverter.convert(document)
      { io: converted.io, filename: "residency_document#{File.extname(converted.filename.to_s)}",
        content_type: converted.content_type, identify: false
}
    rescue IdDocumentConverter::Refused => e
      Rails.logger.info("Residency upload refused: #{e.message}")
      nil
    end

    def failure(check, errors) = Result.new(verification: check, errors:)

  end
end
