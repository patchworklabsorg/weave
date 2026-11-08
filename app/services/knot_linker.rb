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
# - Birth match (name + birth date + country of birth on another Knot, with
#   no strong match to that Knot): the same person, unless the verifiers
#   record that it is not. A second verifier must attend. With no
#   different_person_reason, it acts like a strong match: it stops a pass on
#   a second live account, and it joins a detached Knot (grants and flag
#   carry over). With a written different_person_reason, it only stays a
#   review: nothing links, and the hashes are stored as usual.
# - Legacy match (a US driving licence digest without the state, from before
#   2026-11-08): two states can give the same number. With a soft match to
#   the same Knot (the same number, name and birth date) it counts as
#   strong, and the Knot gets the new digest with the state. Alone it
#   counts as soft.
# - Soft-only match (the name + birth date hash on another Knot, with no
#   strong or birth match to that Knot): routes the pass to manual review with a
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
  REVIEW_REASONS = %w[soft_match birth_match flagged_match].freeze
  REVIEW_RANK = { "soft_match" => 1, "birth_match" => 2, "flagged_match" => 3 }.freeze

  # Raised inside the decision transaction, which rolls the pass back.
  class DuplicateAccount < StandardError; end

  Match = Data.define(:own_knot, :strong_knots, :birth_knots, :soft_only_knots) do
    def strong? = strong_knots.any?

    def birth? = birth_knots.any?

    def soft_only? = soft_only_knots.any?

    # Knots of other live accounts with a strong match.
    def live_conflicts = strong_knots.reject(&:detached?)

    # Knots of other live accounts with a birth match.
    def birth_live_conflicts = birth_knots.reject(&:detached?)

    # A birth match can still be a different person, so its flag stays hidden
    # like a soft match's. It carries over only if the Knots join.
    def flagged? = own_knot&.blacklisted || strong_knots.any?(&:blacklisted)

    # Why the pass needs a second verifier, or nil.
    def review_reason
      return "flagged_match" if flagged?
      return "birth_match" if birth?

      "soft_match" if soft_only?
    end
  end

  # The record the deletion pipeline writes into the deletion receipt.
  Record = Data.define(:knot, :blacklisted, :grants_received)

  class << self
    # legacy: digests that count as soft only (KnotHasher.legacy_digests).
    def match(user, digests, legacy: [])
      # Read from the database: a cached user.knot can be stale here.
      own = (Knot.find_by(user_id: user.id) if user&.id)
      rows = KnotHash.matching(digests).where.not(knot_id: own&.id).to_a
      soft_ids = rows.reject { |row| row.strong? || row.birth? }.map(&:knot_id).uniq
      legacy_ids = KnotHash.matching(legacy).where.not(knot_id: own&.id).pluck(:knot_id).uniq
      # The same licence number with the same name and birth date: the same person.
      strong_ids = rows.select(&:strong?).map(&:knot_id).uniq | (legacy_ids & soft_ids)
      birth_ids = rows.select(&:birth?).map(&:knot_id).uniq - strong_ids
      soft_ids = (soft_ids | legacy_ids) - strong_ids - birth_ids
      Match.new(own_knot: own, strong_knots: Knot.where(id: strong_ids).order(:id).to_a,
                birth_knots: Knot.where(id: birth_ids).order(:id).to_a,
                soft_only_knots: Knot.where(id: soft_ids).order(:id).to_a)
    end

    def match_identifiers(user, identifiers)
      match(user, KnotHasher.digests(identifiers), legacy: KnotHasher.legacy_digests(identifiers))
    end

    # Errors that stop a pass now, before VerificationFlow records it. Opens
    # the manual review (Verification#knot_review_reason) when a match asks
    # for one. The review stays on the attempt, so typing other identifiers
    # does not remove it.
    #
    # different_person_reason: the verifiers' written reason that a birth
    # match is a different person. A second verifier must attend.
    def pass_errors(verification, identifiers:, second_verifier:, different_person_reason: nil)
      if identifiers&.valid?
        found = match_identifiers(verification.user, identifiers)
        if found.live_conflicts.any?
          VerificationEvent.record!(verification, :knot_duplicate_account)
          return { identifiers: I18n.t("knot.errors.duplicate_account") }
        end
        if found.birth_live_conflicts.any? && different_person_reason.blank?
          VerificationEvent.record!(verification, :knot_duplicate_account, birth_match: true)
          open_review(verification, found.review_reason)
          return { identifiers: I18n.t("knot.errors.birth_duplicate_account") }
        end
        open_review(verification, found.review_reason)
      end

      reason = verification.knot_review_reason
      return {} if reason.nil? || second_verifier.present?

      { second_verifier: I18n.t("knot.errors.second_verifier_required.#{reason}") }
    end

    # The subscriber of VerificationIdentifiers::EVENT. On a pass, the hashes
    # join the member's Knot. A fail stores nothing.
    def decision_made(verification:, outcome:, identifiers:, different_person_reason: nil)
      return unless outcome == "verified" && identifiers&.valid? && verification.user

      # The reason counts only when there is a birth match to override.
      birth = match_identifiers(verification.user, identifiers).birth?
      link_birth = !birth || different_person_reason.blank?
      knot, merged = accrete!(verification.user, KnotHasher.digests(identifiers), link_birth:,
                                                                                  legacy: KnotHasher.legacy_digests(identifiers))
      unless link_birth
        VerificationEvent.record!(verification, :knot_birth_match_overridden, reason: different_person_reason.to_s.strip,
                                                                              second_verifier_id: verification.second_verifier_id)
      end
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
    #
    # link_birth: false when the verifiers recorded that a birth match is a
    # different person. Then only strong matches link.
    def accrete!(user, digests, link_birth: true, legacy: [])
      lock_birth_digests!(digests)
      found = match(user, digests, legacy:)
      raise DuplicateAccount, "A strong hash is on another live account's Knot" if found.live_conflicts.any?
      if link_birth && found.birth_live_conflicts.any?
        raise DuplicateAccount, "A birth hash is on another live account's Knot"
      end

      detached = found.strong_knots.dup
      detached.concat(found.birth_knots) if link_birth
      knot = found.own_knot
      if knot.nil?
        knot = detached.shift || Knot.new
        knot.update!(user:)
        user.association(:knot).target = knot
      end
      merged = found.strong_knots.size + (link_birth ? found.birth_knots.size : 0)
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

    # Birth digests are not unique, so the database can't stop two passes at
    # the same time from both missing each other. A transaction lock on each
    # birth digest (sorted, so two passes never wait on each other in a
    # circle) makes the second pass wait and then see the first.
    def lock_birth_digests!(digests)
      digests.select { |found| found.kind == "birth" }.map(&:digest).sort.each do |value|
        Knot.connection.execute(Knot.sanitize_sql_array(["SELECT pg_advisory_xact_lock(hashtextextended(?, 0))", "knot-birth:#{value}"]))
      end
    end

    def open_review(verification, reason)
      return if reason.nil? || verification.knot_review_reason == reason
      # The stronger reason stays.
      return if REVIEW_RANK.fetch(verification.knot_review_reason, 0) > REVIEW_RANK.fetch(reason)

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
