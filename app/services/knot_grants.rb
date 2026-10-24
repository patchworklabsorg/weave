# frozen_string_literal: true

# Program grants and their per-program caps (see ProgramGrant, KnotSettings
# and docs/KYC.md). Grants are keyed to the Knot, not to the user, so a member
# who deletes their account and returns with the same document gets the same
# Knot back (see KnotLinker) and the same grant count.
#
# - The program's patch lead (config/kyc/knot.yml) records a grant. An owner
#   can too.
# - A grant needs a Knot (a passed verification), a Knot that is not
#   blacklisted, and room under the program's cap. A cap of nil means no cap.
# - Over the cap, the patch lead asks for an override with a written reason
#   and a board member signs it off (KnotChanges). The reason goes into the
#   verification audit record.
module KnotGrants
  Result = Data.define(:grant, :errors) do
    def success? = errors.empty?
  end

  class << self
    # :eligible, :unknown_program, :not_verified, :blacklisted or :cap_reached.
    def eligibility(user, program)
      settings = KnotSettings.program(program)
      return :unknown_program if settings.nil?

      knot = user&.knot
      return :not_verified if knot.nil?
      return :blacklisted if knot.blacklisted
      return :cap_reached if settings.grant_cap && knot.grants_received(settings.key) >= settings.grant_cap

      :eligible
    end

    def eligible?(user, program) = eligibility(user, program) == :eligible

    # Grants left under the cap, or nil when the program has no cap.
    def remaining(user, program)
      settings = KnotSettings.program(program)
      return nil if settings&.grant_cap.nil?

      [settings.grant_cap - (user&.knot&.grants_received(settings.key) || 0), 0].max
    end

    # The patch lead of a program holds the patch_lead role scoped to the
    # program key (see RoleGrants and config/roles.yml).
    def patch_lead?(user, program)
      settings = KnotSettings.program(program)
      user.present? && settings.present? && user.has_role?("patch_lead", scope: settings.key)
    end

    # True when the user leads any program.
    def any_patch_lead?(user) = user.present? && user.role_scopes("patch_lead").intersect?(KnotSettings.program_keys)

    def record(user, program:, by:)
      program = program.to_s
      return failure(base: "Only the program's patch lead or an owner can record a grant.") unless can_record?(by, program, user)

      eligibility = eligibility(user, program)
      return failure(base: I18n.t("knot.grants.#{eligibility}")) unless eligibility == :eligible

      knot = user.knot
      grant = nil
      Knot.transaction do
        knot.lock!
        # Read the count again under the lock, so two clicks can't pass the cap.
        return failure(base: I18n.t("knot.grants.cap_reached")) unless eligible?(user, program)

        grant = knot.program_grants.create!(program:, granted_at: Time.current)
        # The participation record, which folds into the delete-time
        # aggregates when the member deletes the account (DeletionPipeline).
        ProgramParticipation.record!(user, program:, outcome: "granted")
        audit = knot.audit_verification
        VerificationEvent.record!(audit, :program_grant_recorded, actor: by, program:, knot: knot.public_id) if audit
      end
      Result.new(grant:, errors: {})
    end

    # The patch lead asks for a grant over the cap. A board member signs off
    # (KnotChanges.sign_off).
    def request_override(user, program:, by:, reason:)
      program = program.to_s
      return failure(base: "Only the program's patch lead can ask for an override.") unless patch_lead?(by, program) && by != user

      eligibility = eligibility(user, program)
      return failure(base: I18n.t("knot.grants.override_not_needed")) if eligibility == :eligible
      return failure(base: I18n.t("knot.grants.#{eligibility}")) unless eligibility == :cap_reached
      return failure(reason: "is required") if reason.to_s.strip.blank?

      result = KnotChanges.create_request(user.knot, by:, kind: "grant_override", program:, reason: reason.to_s.strip)
      result.success? ? Result.new(grant: nil, errors: {}) : failure(result.errors)
    end

    private

    def can_record?(by, program, user)
      return false if by.nil? || by == user

      by.owner? || patch_lead?(by, program)
    end

    def failure(errors) = Result.new(grant: nil, errors:)

  end
end
