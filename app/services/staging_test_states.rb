# frozen_string_literal: true

# Staging only: an owner puts a member's identity verification, US residency
# or guardian consent straight into a state, so the team can test what each
# state does. On production none of this exists: allowed? is false and the
# admin page does not show the tools (see Admin::StagingTestStatesController).
#
# Each change first removes the member's records of that kind, then writes
# one record in the new state. The records carry no ID images or document
# data, like IdentityGovernance.staging_seed!. The VerificationEvent rows of
# the removed attempts go too: on staging the history is test data.
module StagingTestStates
  REASON = "Staging test state"

  AREAS = {
    "identity"         => "Identity verification",
    "residency"        => "US residency",
    "guardian_consent" => "Guardian consent"
  }.freeze

  STATES = {
    "identity"         => {
      "none"                    => "Not submitted",
      "verified"                => "Passed",
      "reverification_required" => "Passed, needs a new call",
      "failed"                  => "Failed"
    },
    "residency"        => {
      "none"            => "Not checked",
      "us_resident"     => "US resident",
      "not_us_resident" => "Not a US resident"
    },
    "guardian_consent" => {
      "none"     => "No consent",
      "granted"  => "Granted",
      "verified" => "Granted and verified"
    }
  }.freeze

  class Error < StandardError; end

  module_function

  def allowed?(actor) = Weave.staging? && actor.present? && actor.owner?

  # Sets one area (a key of STATES) of the member to a state. Raises Error
  # when the actor may not, or the area or state is not known.
  def set!(user, area:, state:, by:, us_state: nil)
    raise Error, "Only an owner can set test states, and only on staging." unless allowed?(by)
    raise Error, "Unknown test state." unless STATES.dig(area.to_s, state.to_s)

    PaperTrail.request(whodunnit: by.id) do
      ApplicationRecord.transaction do
        case area.to_s
        when "identity" then set_identity!(user, state.to_s, by:)
        when "residency" then set_residency!(user, state.to_s, by:, us_state:)
        when "guardian_consent" then set_guardian_consent!(user, state.to_s, by:)
        end
      end
    end
  end

  def set_identity!(user, state, by:)
    clear_identity!(user)
    return if state == "none"

    verified = state != "failed"
    verification = Verification.new(
      user:, verification_method: "document_call", document_type: "other",
      status: verified ? "verified" : "failed", verifier: by, decided_at: Time.current,
      decision_reason: REASON, age_consistent: true, region_consistent: true
    )
    # No ID image on purpose, so skip the attachment check.
    verification.save!(validate: false)
    VerificationEvent.record!(verification, :decided, actor: by, outcome: verification.status, reason: REASON,
                                                       verifier_id: by.id, staging_test_state: true)
    return unless verified

    # Program grants need a Knot. A test Knot has no hashes.
    knot = Knot.create!(user:)
    verification.update_columns(knot_id: knot.id) # rubocop:disable Rails/SkipsModelValidations
    return unless state == "reverification_required"

    verification.update!(reverification_required_at: Time.current, reverification_reason: "birthday_changed")
    VerificationEvent.record!(verification, :reverification_required, actor: by, reason: "birthday_changed",
                                                                      staging_test_state: true)
  end

  def set_residency!(user, state, by:, us_state: nil)
    clear_residency!(user)
    return if state == "none"

    us_resident = state == "us_resident"
    us_state = us_state.presence || "MA" if us_resident
    raise Error, "Unknown US state." if us_resident && !ResidencyCheck::US_STATES.key?(us_state)

    check = ResidencyCheck.new(
      user:, source: "document_review", status: "decided", evidence_type: ResidencyCheck::MEMBER_STATEMENT,
      us_resident:, us_state: (us_state if us_resident), decided_by: by, decided_at: Time.current
    )
    # No document on purpose, so skip the evidence checks.
    check.save!(validate: false)
  end

  def set_guardian_consent!(user, state, by:)
    raise Error, "Guardian consent applies only to members under 18." if state != "none" && !user.minor?

    user.guardian_consents.find_each(&:destroy!)
    return if state == "none"

    consent = GuardianConsent.record_offline!(
      user, guardian_name: "Staging Guardian", guardian_email: "guardian+#{user.p_id.downcase}@example.com",
            recorded_by: by, note: REASON
    )
    raise Error, consent.errors.full_messages.to_sentence unless consent.persisted?

    consent.record_verification!(by:, note: REASON) if state == "verified"
  end

  def clear_identity!(user)
    ids = user.verifications.pluck(:id)
    if ids.any?
      records = BreakGlassRecord.where(verification_id: ids)
      decryptions = BreakGlassDecryption.where(break_glass_record: records)
      BreakGlassNotice.where(break_glass_decryption: decryptions).delete_all
      decryptions.delete_all
      BreakGlassApproval.where(break_glass_record: records).delete_all
      records.delete_all
      SealedIdDocument.where(verification_id: ids).delete_all
      VerificationEvent.where(verification_id: ids).delete_all
      ResidencyCheck.where(verification_id: ids).update_all(verification_id: nil) # rubocop:disable Rails/SkipsModelValidations
      Verification.where(id: ids).find_each { |verification| verification.id_document.purge }
      Verification.where(id: ids).delete_all
    end
    Knot.where(user:).find_each(&:destroy!)
    user.association(:knot).reset
  end

  def clear_residency!(user)
    checks = user.residency_checks
    SealedResidencyDocument.where(residency_check: checks).delete_all
    checks.find_each { |check| check.document.purge }
    checks.delete_all
  end
end
