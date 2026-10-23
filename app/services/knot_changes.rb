# frozen_string_literal: true

# Two-key changes to a Knot (see Knot, KnotChangeRequest and docs/KYC.md).
# One person asks with a written reason. A second, different person signs off.
# Nobody changes a Knot alone, and nobody signs off a change to their own Knot.
#
# - Blacklist flag (set or clear): two identity team members. Each applied
#   change is a blacklist review, so the member must verify again.
# - Legal name change: an identity team member checks continuity (the new
#   document or the change-of-name record, against the member they know),
#   types the new identifiers, and a second identity team member signs off.
#   The new hashes join the set. The old hashes stay, and the flag and the
#   grants carry over untouched. The member's pass stops standing, so they
#   verify again (legal_name_changed).
# - Grant over the cap: see KnotGrants.request_override. A board member signs
#   off.
#
# The reason and each step go into the verification audit record
# (VerificationEvent on Knot#audit_verification), never onto the Knot. The
# request row is deleted when it is signed off or declined.
module KnotChanges
  Result = Data.define(:request, :errors) do
    def success? = errors.empty?
  end

  NAME_CHANGE_EVIDENCE = %w[new_document change_of_name_record].freeze

  class << self
    def request_blacklist(knot, by:, blacklisted:, reason:)
      reason = reason.to_s.strip
      return failure(base: "Only an identity team member can ask, and not for their own Knot.") unless identity_member?(by, knot)
      return failure(reason: "is required") if reason.blank?
      return failure(base: "The flag is already #{blacklisted ? 'set' : 'clear'}.") if knot.blacklisted == blacklisted

      create_request(knot, by:, kind: blacklisted ? "set_blacklist" : "clear_blacklist", reason:)
    end

    # identifiers is a VerificationIdentifiers. Legal name and birth date are
    # required. With a new document, its type, country and number are
    # required too. Only the hashes are kept.
    def request_name_change(user, by:, evidence:, note:, identifiers:)
      knot = user&.knot
      note = note.to_s.strip
      return failure(base: "The member has no Knot: they have not passed verification.") if knot.nil?
      return failure(base: "Only an identity team member can ask, and not for their own name.") unless identity_member?(by, knot)
      return failure(evidence: "must be a new document or a change-of-name record") unless NAME_CHANGE_EVIDENCE.include?(evidence)
      return failure(note: "is required: write how you checked continuity") if note.blank?

      errors = name_change_errors(evidence, identifiers)
      return failure(errors) if errors.any?

      existing = knot.knot_hashes.pluck(:kind, :digest)
      digests = KnotHasher.digests(identifiers).reject { |found| existing.include?([found.kind, found.digest]) }
      return failure(base: "These identifiers are already on the Knot.") if digests.empty?

      create_request(knot, by:, kind: "name_change", reason: note, evidence:, digests: digests.map(&:to_h))
    end

    def sign_off(request, by:)
      return failure(base: "A second, different person must sign off.") unless can_sign_off?(request, by)

      knot = request.knot
      errors = {}
      Knot.transaction do
        knot.lock!
        errors = apply(request, knot)
        raise ActiveRecord::Rollback if errors.any?

        VerificationEvent.record!(request.verification, :knot_change_signed_off, actor: by, change: request.kind,
                                                                                 knot: knot.public_id, program: request.program)
        request.destroy!
      end
      # A blacklist review and a legal name change are re-verification
      # triggers: the member's pass stops standing and they need a new call
      # (see VerificationFlow.require_reverification).
      if errors.empty? && knot.user
        reason = reverification_reason(request)
        # require_reverification ends only a standing pass, so a second
        # trigger for the same change (for example a later edit of
        # users.legal_* for the same name) does nothing.
        VerificationFlow.require_reverification(knot.user, reason:, actor: by) if reason
      end
      errors.any? ? Result.new(request:, errors:) : Result.new(request:, errors: {})
    end

    # The second person declines, or the requester withdraws.
    def decline(request, by:, reason:)
      reason = reason.to_s.strip
      unless can_sign_off?(request, by) || (by.present? && by.id == request.requested_by_id)
        return failure(base: "Only the requester or a possible second signer can decline.")
      end
      return failure(reason: "is required") if reason.blank?

      KnotChangeRequest.transaction do
        VerificationEvent.record!(request.verification, :knot_change_declined, actor: by, change: request.kind,
                                                                               knot: request.knot.public_id, reason:)
        request.destroy!
      end
      Result.new(request:, errors: {})
    end

    # Who may sign off: never the requester or the member, and for a grant
    # override a board member, else an identity team member.
    def can_sign_off?(request, by)
      return false if by.nil? || by.id == request.requested_by_id || by.id == request.knot.user_id

      request.kind == "grant_override" ? by.board? : by.identity_team
    end

    # Used by KnotGrants too.
    def create_request(knot, by:, kind:, reason:, program: nil, evidence: nil, digests: [])
      verification = knot.audit_verification
      return failure(base: "The Knot has no verification audit record to hold the reason.") if verification.nil?

      request = knot.change_requests.new(kind:, program:, digests:, verification:, requested_by: by)
      KnotChangeRequest.transaction do
        request.save || raise(ActiveRecord::Rollback)
        VerificationEvent.record!(verification, :knot_change_requested, actor: by, change: kind, knot: knot.public_id,
                                                                        program:, evidence:, reason:)
      end
      return failure(request.errors.to_hash.transform_values(&:first)) unless request.persisted?

      Result.new(request:, errors: {})
    end

    private

    def apply(request, knot)
      case request.kind
      when "set_blacklist" then knot.update!(blacklisted: true)
      when "clear_blacklist" then knot.update!(blacklisted: false)
      when "name_change"
        return { base: "The account was deleted, so the name can't change." } if knot.user.nil?

        KnotLinker.accrete!(knot.user, request.new_digests)
      when "grant_override"
        return { base: "The Knot is blacklisted. An override does not lift the flag." } if knot.blacklisted

        knot.program_grants.create!(program: request.program, granted_at: Time.current)
      end
      {}
    rescue KnotLinker::DuplicateAccount, ActiveRecord::RecordNotUnique
      { base: I18n.t("knot.errors.duplicate_account") }
    end

    def name_change_errors(evidence, identifiers)
      return { identifiers: "are required" } if identifiers.nil?

      errors = identifiers.errors.slice(:legal_name, :date_of_birth, :issuing_country, :document_type)
      if evidence == "new_document"
        errors.merge!(identifiers.errors.slice(:document_number))
      else
        errors.delete(:issuing_country) if identifiers.issuing_country.nil?
        errors.delete(:document_type) if identifiers.document_type.nil?
      end
      errors
    end

    def reverification_reason(request)
      if request.blacklist_change? then "blacklist_review"
      elsif request.kind == "name_change" then "legal_name_changed"
      end
    end

    def identity_member?(by, knot) = by&.identity_team && by.id != knot.user_id

    def failure(errors) = Result.new(request: nil, errors:)

  end
end
