# frozen_string_literal: true

# Grants and revokes staff and identity roles (see Role, UserRole, the rules
# in config/roles.yml and docs/KYC.md "Roles").
#
# Two layers:
#
# - .grant! and .revoke! write the rows. They check the role, the scope, the
#   required roles and the key holder limit, but not who acts. Only rule
#   checked callers use them: .grant and .revoke below, IdentityGovernance
#   (proposals, removals, the bootstrap), the data migration, and the
#   compatibility setters on User (console and specs).
# - .grant and .revoke apply an immediate rule (owner, any_owner, admin,
#   owner_or_identity_lead) for the acting user. A role with a proposal
#   rule goes through IdentityGovernance.propose instead.
#
# Every write names the actor for the permanent log (see
# PrivilegedChangeActor). After the commit, the person's system groups follow
# the change (see SystemGroups).
module RoleGrants
  class Error < StandardError; end

  Result = Data.define(:record, :errors) do
    def success? = errors.empty?

    def message = errors.map { |key, text| key == :base ? text : "#{key.to_s.humanize} #{text}" }.join(". ")
  end

  RULE_TEXT = {
    "owner_proposes_board_approves" => "An owner proposes. A different board member approves.",
    "owner_proposes_all_board_approve" => "An owner proposes. Every board member approves.",
    "owner" => "One owner, at once.",
    "any_owner" => "One owner, at once, for any person, other owners too.",
    "admin" => "Any admin, at once.",
    "owner_or_identity_lead" => "One owner or identity lead, at once."
  }.freeze

  class << self
    # -- Rules -----------------------------------------------------------

    def rule(key, action) = RoleRegistry.fetch(key).rule_for(action)

    def rule_text(key, action) = RULE_TEXT.fetch(rule(key, action).rule)

    def proposal?(key, action) = rule(key, action).proposal?

    # True when `by` may grant or revoke the role of `user` at once, under an
    # immediate rule. False for a proposal rule.
    def allowed_now?(by, user, key, action)
      return false if by.nil? || user.nil?

      case rule(key, action).rule
      when "owner" then by.owner? && UserAdminPermissions.new(by, user).manage?
      # The board role: any owner, for any person, other owners too. No peer
      # rule (UserAdminPermissions#manage?).
      when "any_owner" then by.owner?
      when "admin" then by.admin? && UserAdminPermissions.new(by, user).manage?
      when "owner_or_identity_lead" then by.owner? || (by.identity_team && by.identity_lead)
      else false
      end
    end

    # Grants a role with an immediate rule. Returns a Result.
    def grant(user, key, by:, reason: nil, scope: nil)
      key = key.to_s
      return failure(base: "Choose a person.") if user.nil?
      return failure(base: proposal_message(key, "grant")) if proposal?(key, :grant)
      return failure(base: "You can't grant the #{RoleRegistry.fetch(key).name.downcase} role to #{user.full_name}.") unless allowed_now?(by, user, key, :grant)
      return failure(base: "#{user.full_name} already has this role.") if user.has_role?(key, scope:)

      record = nil
      with_actor(by) do
        User.transaction do
          record = grant!(user, key, scope:, by:, reason:)
          after_immediate_change(user, key, by)
        end
      end
      success(record)
    rescue Error, ActiveRecord::RecordInvalid => error
      failure(base: error.message)
    end

    # Revokes a role with an immediate rule. Returns a Result.
    def revoke(user, key, by:, reason: nil, scope: nil)
      key = key.to_s
      return failure(base: "Choose a person.") if user.nil?
      return failure(base: proposal_message(key, "revoke")) if proposal?(key, :revoke)
      return failure(base: "You can't revoke the #{RoleRegistry.fetch(key).name.downcase} role of #{user.full_name}.") unless allowed_now?(by, user, key, :revoke)
      return failure(base: "#{user.full_name} does not have this role.") unless user.has_role?(key, scope:)

      # Removing a verifier closes their proposals, tells the board and runs
      # the key holder hook: IdentityGovernance owns that path.
      if key == "verifier"
        result = IdentityGovernance.remove_member(user, by:, reason:)
        return result.success? ? success(result.record) : failure(result.errors)
      end

      rows = nil
      with_actor(by) do
        User.transaction do
          rows = revoke!(user, key, scope:, by:, reason:)
          after_immediate_change(user, key, by)
        end
      end
      success(rows)
    rescue Error => error
      failure(base: error.message)
    end

    # -- Storage ---------------------------------------------------------

    # Writes an active assignment. Returns the existing row when the person
    # already holds the role with this scope. Raises Error on a bad role,
    # scope, missing required role or a full set of key holders.
    def grant!(user, key, scope: nil, by: nil, reason: nil, proposal: nil)
      key = key.to_s
      definition = RoleRegistry.fetch(key)
      scope = scope.presence&.to_s
      raise Error, "#{user.full_name} needs a saved account first." unless user.persisted?
      raise Error, scope_error(definition, scope) unless RoleRegistry.valid_scope?(key, scope)

      existing = active_rows(user, key, scope).first
      return existing if existing

      missing = definition.requires.reject { |required| user.has_role?(required) }
      if missing.any?
        raise Error, "#{user.full_name} must be #{missing.map { |required| RoleRegistry.fetch(required).name.downcase }.to_sentence} first."
      end

      record = nil
      with_actor(by) do
        UserRole.transaction do
          check_key_holder_limit!(user) if key == "key_holder"
          record = UserRole.create!(user:, role: Role.fetch!(key), scope:, granted_by: by, granted_at: Time.current,
                                    reason: reason.presence, identity_governance_proposal: proposal)
        end
      end
      changed!(user)
      record
    end

    # Revokes the active assignment, and the roles that require it (a
    # removed verifier is no longer a key holder or lead). Returns the
    # revoked rows. A role the person does not hold is a no-op.
    def revoke!(user, key, scope: nil, by: nil, reason: nil)
      key = key.to_s
      RoleRegistry.fetch(key)
      scope = scope.presence&.to_s
      rows = []
      with_actor(by) do
        UserRole.transaction do
          RoleRegistry.dependents_of(key).each { |dependent| rows.concat(revoke!(user, dependent, by:, reason:)) }
          active_rows(user, key, scope).lock.each do |row|
            row.update!(revoked_at: Time.current, revoked_by: by, revoke_reason: reason.presence)
            rows << row
          end
        end
      end
      changed!(user) if rows.any?
      rows
    end

    # Revokes every active role of a person (account deletion). Returns the
    # revoked rows.
    def revoke_all!(user, by: nil, reason: nil)
      rows = []
      with_actor(by) do
        UserRole.transaction do
          UserRole.active.where(user:).lock.each do |row|
            row.update!(revoked_at: Time.current, revoked_by: by, revoke_reason: reason.presence)
            rows << row
          end
        end
      end
      changed!(user) if rows.any?
      rows
    end

    # -- Reading ---------------------------------------------------------

    # The active assignments of a role, oldest first, with the people
    # preloaded.
    def assignments(key)
      UserRole.active.for_role(key).includes(:user).order(:granted_at, :id)
    end

    private

    def active_rows(user, key, scope)
      UserRole.active.for_role(key).where(user:, scope:)
    end

    # At most VerificationSettings.max_key_holders. The lock serializes two
    # grants at the same time (the same lock as IdentityGovernance).
    def check_key_holder_limit!(user)
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{IdentityGovernance::KEY_HOLDER_LOCK})")
      others = User.identity_key_holders.where.not(id: user.id).count
      return if others < VerificationSettings.max_key_holders

      raise Error, "There are already #{others} key holders. Remove one first."
    end

    def scope_error(definition, scope)
      if definition.scopable?
        "The #{definition.name.downcase} role needs a scope, one of: #{RoleRegistry.scopes_for(definition.key).join(', ')} (got #{scope.inspect})."
      else
        "The #{definition.name.downcase} role is global: it takes no scope."
      end
    end

    def proposal_message(key, action)
      "The #{RoleRegistry.fetch(key).name.downcase} role needs a proposal on the identity governance page to #{action} it. #{rule_text(key, action)}"
    end

    # The board is told about each change (see IdentityGovernance.board_changed!).
    def after_immediate_change(user, key, by)
      IdentityGovernance.board_changed!(user, by:) if key == "board"
    end

    # Drops the cached roles, and syncs the system groups after the commit.
    def changed!(user)
      user.reload_roles!
      ActiveRecord.after_all_transactions_commit do
        user.reload_roles!
        SystemGroups.sync(user) if user.persisted? && User.exists?(user.id)
      end
    end

    def with_actor(by, &block)
      by ? PrivilegedChangeActor.with(actor: by, &block) : yield
    end

    def success(record) = Result.new(record:, errors: {})

    def failure(errors) = Result.new(record: nil, errors:)

  end
end
