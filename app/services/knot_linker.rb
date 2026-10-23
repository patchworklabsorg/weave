# frozen_string_literal: true

# Links passed verifications to the Knot (see Knot and docs/KYC.md).
#
# Matching, at each pass:
# - The member's own live Knot never counts as a match.
# - Strong match (a document or national ID hash on another Knot): the same
#   person. A detached Knot (from a deleted account) joins the member's Knot:
#   its hashes, its grants and its flag carry over, and its attempts link to
#   the same history. A strong match to the Knot of another LIVE account
#   stops the pass: one person, one account. The verifier can still fail the
#   call with a written reason.
# - Soft-only match (the name + birth date hash on another Knot, with no
#   strong match to that Knot): routes the pass to manual review with a
#   second verifier. That is all it can do. It never fails, blocks or flags
#   anyone, and it never links Knots or carries a flag over.
# - A blacklisted Knot in a strong match, or a blacklisted own Knot, also
#   routes the pass to a second verifier (extra scrutiny).
#
# The hashes come from the identifiers the verifier types at the decision.
# VerificationFlow calls pass_errors before it records a pass, and the
# subscriber of VerificationIdentifiers::EVENT calls decision_made inside the
# transaction of the decision. The plain identifiers are dropped after that.
module KnotLinker
  REVIEW_REASONS = %w[soft_match flagged_match].freeze

  # Raised inside the decision transaction, which rolls the pass back.
  class DuplicateAccount < StandardError; end

  Match = Data.define(:own_knot, :strong_knots, :soft_only_knots) do
    def strong? = strong_knots.any?

    def soft_only? = soft_only_knots.any?

    # Knots of other live accounts with a strong match.
    def live_conflicts = strong_knots.reject(&:detached?)

    def flagged? = own_knot&.blacklisted || strong_knots.any?(&:blacklisted)

    # Why the pass needs a second verifier, or nil.
    def review_reason
      return "flagged_match" if flagged?

      "soft_match" if soft_only?
    end
  end

  # The record the deletion pipeline writes into the deletion receipt.
  Record = Data.define(:knot, :blacklisted, :grants_received)

  class << self
    def match(user, digests)
      # Read from the database: a cached user.knot can be stale here.
      own = (Knot.find_by(user_id: user.id) if user&.id)
      rows = KnotHash.matching(digests).where.not(knot_id: own&.id).to_a
      strong_ids = rows.select(&:strong?).map(&:knot_id).uniq
      soft_ids = rows.reject(&:strong?).map(&:knot_id).uniq - strong_ids
      Match.new(own_knot: own, strong_knots: Knot.where(id: strong_ids).order(:id).to_a,
                soft_only_knots: Knot.where(id: soft_ids).order(:id).to_a)
    end

    # Errors that stop a pass now, before VerificationFlow records it. Opens
    # the manual review (Verification#knot_review_reason) when a match asks
    # for one. The review stays on the attempt, so typing other identifiers
    # does not remove it.
    def pass_errors(verification, identifiers:, second_verifier:)
      if identifiers&.valid?
        found = match(verification.user, KnotHasher.digests(identifiers))
        if found.live_conflicts.any?
          VerificationEvent.record!(verification, :knot_duplicate_account)
          return { identifiers: I18n.t("knot.errors.duplicate_account") }
        end
        open_review(verification, found.review_reason)
      end

      reason = verification.knot_review_reason
      return {} if reason.nil? || second_verifier.present?

      { second_verifier: I18n.t("knot.errors.second_verifier_required.#{reason}") }
    end

    # The subscriber of VerificationIdentifiers::EVENT. On a pass, the hashes
    # join the member's Knot. A fail stores nothing.
    def decision_made(verification:, outcome:, identifiers:)
      return unless outcome == "verified" && identifiers&.valid? && verification.user

      knot, merged = accrete!(verification.user, KnotHasher.digests(identifiers))
      # The whole chain of attempts links to the Knot, failed calls too, so
      # the history of a returning member reads as one chain.
      chain = Verification.where(id: verification.chain.map(&:id))
      chain.where(knot_id: nil).or(chain.where(id: verification.id)).update_all(knot_id: knot.id) # rubocop:disable Rails/SkipsModelValidations
      verification.knot_id = knot.id
      VerificationEvent.record!(verification, :knot_linked, knot: knot.public_id, returning: merged.positive?,
                                                            grants_received: grants_received(knot))
    end

    # Adds the digests to the member's Knot. Creates the Knot, or adopts a
    # detached Knot with a strong match, when the member has none. Joins every
    # other detached Knot with a strong match. Returns [knot, the number of earlier Knots it joined].
    def accrete!(user, digests)
      found = match(user, digests)
      raise DuplicateAccount, "A strong hash is on another live account's Knot" if found.live_conflicts.any?

      detached = found.strong_knots.dup
      knot = found.own_knot
      if knot.nil?
        knot = detached.shift || Knot.new
        knot.update!(user:)
        user.association(:knot).target = knot
      end
      merged = found.strong_knots.size
      detached.each { |other| merge!(knot, other) }
      digests.each { |found_digest| knot.knot_hashes.find_or_create_by!(kind: found_digest.kind, digest: found_digest.digest) }
      [knot, merged]
    end

    # The deletion pipeline calls this before it severs the identity (step 2
    # of 4). The blacklist flag and the grants received are already on the
    # Knot, so it only drops the requests that need a live member and
    # detaches the Knot. Returns the Record for the deletion receipt, or nil
    # when the member never passed.
    def write_record_and_detach!(user)
      knot = Knot.find_by(user_id: user.id)
      return nil if knot.nil?

      Knot.transaction do
        knot.lock!
        knot.change_requests.where(kind: %w[name_change grant_override]).delete_all
        knot.update!(user: nil)
      end
      user.association(:knot).reset
      Record.new(knot:, blacklisted: knot.blacklisted, grants_received: grants_received(knot))
    end

    def grants_received(knot) = knot.program_grants.group(:program).count

    private

    def open_review(verification, reason)
      return if reason.nil? || verification.knot_review_reason == reason
      return if verification.knot_review_reason == "flagged_match" # The stronger reason stays.

      verification.update!(knot_review_reason: reason)
      VerificationEvent.record!(verification, :knot_review_required, reason:)
    end

    # other joins into: hashes, grants, attempts and the flag. Then other is
    # deleted.
    def merge!(into, other)
      other.knot_hashes.each do |row|
        if into.knot_hashes.exists?(kind: row.kind, digest: row.digest)
          row.delete
        else
          row.update_columns(knot_id: into.id) # rubocop:disable Rails/SkipsModelValidations
        end
      end
      other.program_grants.update_all(knot_id: into.id) # rubocop:disable Rails/SkipsModelValidations
      Verification.where(knot_id: other.id).update_all(knot_id: into.id) # rubocop:disable Rails/SkipsModelValidations
      other.change_requests.each do |request|
        if into.change_requests.exists?(kind: request.kind, program: request.program)
          request.delete
        else
          request.update_columns(knot_id: into.id) # rubocop:disable Rails/SkipsModelValidations
        end
      end
      into.update!(blacklisted: true) if other.blacklisted
      other.reload.delete
    end

  end
end
