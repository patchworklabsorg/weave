# frozen_string_literal: true

# Who may be on the identity team, and how the team changes (locked by Jasper
# on 2026-10-12, see docs/KYC.md "Identity team governance").
#
# - Add a verifier: an owner proposes with a reason, and a different board
#   member approves. Nobody approves their own proposal or a proposal about
#   themselves. At the approval, the candidate must be verified (by another
#   person) and at least verifier_minimum_age. NDAs are signed outside Weave
#   (Adobe Acrobat Sign): the approver confirms the NDA before they approve.
# - Make or unmake a lead: the same two-person rule. A new lead must be
#   verified by another verifier.
# - Add or remove a key holder: an owner proposes, and every board member at
#   proposal time approves. A new key holder must be verified by another
#   verifier. The change applies only after the last approval.
#   Each applied change sends KEY_HOLDERS_CHANGED.
# - Remove a member: at once, by any one owner or identity team lead, with a
#   reason. It also revokes the key holder and lead roles. The board gets an
#   email.
# - Make someone the patch lead of a program: an owner proposes, and a
#   different board member approves. The program must be in
#   config/kyc/knot.yml. One owner removes a patch lead at once (RoleGrants).
# - A pending proposal expires after proposal_expiry_days.
#
# The roles are rows in user_roles (see RoleGrants). The rule of each change
# comes from config/roles.yml: a proposal kind is allowed only while the rule
# of its role is a proposal rule, and the preconditions are the ones the
# config names. Every step adds an IdentityGovernanceEvent. PaperTrail records
# each change to a proposal, and the permanent log records each role change.
module IdentityGovernance
  # Sent after the commit of every change to the set of key holders. The
  # key custody work subscribes to it to force a rotation of the master key.
  # Payload: user (the key holder added or removed), change (:added or
  # :removed), holder_ids (the key holders after the change), proposal (nil
  # for a removal from the team), actor.
  KEY_HOLDERS_CHANGED = "key_holders_changed.identity"

  Result = Data.define(:record, :errors) do
    def success? = errors.empty?

    def message = errors.map { |key, text| key == :base ? text : "#{key.to_s.humanize} #{text}" }.join(". ")
  end

  # One precondition for a new verifier, as shown on the proposal.
  Precondition = Data.define(:key, :met, :detail)

  # A key holder change needs every board member. With fewer than two on
  # the board, one person could approve it alone.
  MINIMUM_BOARD_FOR_KEY_HOLDERS = 2

  # Serializes the changes to the set of key holders, so two proposals that
  # apply at the same time can't go over VerificationSettings.max_key_holders.
  KEY_HOLDER_LOCK = 0x1D6B17

  # The role and the direction of each proposal kind. The rule and the
  # preconditions come from config/roles.yml (see RoleGrants.rule).
  KIND_ROLES = {
    "add_member"        => ["verifier", :grant],
    "set_lead"          => ["identity_lead", :grant],
    "clear_lead"        => ["identity_lead", :revoke],
    "add_key_holder"    => ["key_holder", :grant],
    "remove_key_holder" => ["key_holder", :revoke],
    "add_patch_lead"    => ["patch_lead", :grant]
  }.freeze

  # The keys of .preconditions for the precondition names of the config.
  PRECONDITION_KEYS = {
    "verified_by_another"   => :verified,
    "verified_or_bootstrap" => :verified_or_bootstrap,
    "adult"                 => :adult
  }.freeze

  class << self
    # -- Who may do what -------------------------------------------------

    # Owners and board members read the governance page. Identity team leads
    # read it too, because they can remove a member.
    def can_view?(user) = user.present? && (user.owner? || user.is_board || lead?(user))

    def can_propose?(user) = user.present? && user.owner?

    def can_remove?(by, subject)
      by.present? && subject.present? && subject.identity_team && (by.owner? || lead?(by))
    end

    def can_approve?(proposal, by)
      return false unless by&.is_board && proposal.pending?
      return false if proposal.approvals.exists?(approver_id: by.id)

      if proposal.all_board?
        proposal.required_approver_ids.include?(by.id)
      else
        by.id != proposal.proposed_by_id && by.id != proposal.subject_id
      end
    end

    # The proposer withdraws, or an owner withdraws for them.
    def can_withdraw?(proposal, by) = proposal.pending? && by.present? && (by.id == proposal.proposed_by_id || by.owner?)

    # Board members who may still approve the proposal.
    def eligible_approvers(proposal)
      User.board_members.with_roles.select { |user| can_approve?(proposal, user) }
    end

    # The role key and the direction (:grant or :revoke) of a proposal kind.
    def kind_role(kind) = KIND_ROLES.fetch(kind.to_s)

    # The rule of a proposal kind, from config/roles.yml.
    def kind_rule(kind)
      key, action = kind_role(kind)
      RoleGrants.rule(key, action)
    end

    # The kinds an owner can propose now: the kinds whose role has a proposal
    # rule in the config.
    def proposable_kinds = IdentityGovernanceProposal::KINDS.select { |kind| kind_rule(kind).proposal? }

    # -- Preconditions for a verifier ------------------------------------

    def preconditions(user)
      latest = user.latest_verification
      verified = user.identity_verified? && latest.verifier_id != user.id
      age = user.age_in_years
      minimum = IdentityGovernanceSettings.verifier_minimum_age
      age_exception = IdentityGovernanceSettings.verifier_age_exceptions.include?(user.p_id.to_s)

      [
        Precondition.new(
          key: :verified, met: verified,
          detail: if verified
                    "Verified on #{latest.decided_at&.to_date&.iso8601} by #{latest.verifier&.full_name || 'a deleted user'}."
                  else
                    "Not verified by another verifier. Status: #{user.verification_status.humanize.downcase}."
                  end
        ),
        Precondition.new(
          key: :adult, met: age.present? && (age >= minimum || age_exception),
          detail: if age.nil? then "No birthday on record."
                  elsif age < minimum && age_exception then "#{age} years old: under #{minimum}, allowed by an age exception in the config."
                  else "#{age} years old (at least #{minimum} needed)."
                  end
        )
      ]
    end

    def preconditions_met?(user) = preconditions(user).all?(&:met)

    # -- Proposals -------------------------------------------------------

    def propose(kind:, subject:, by:, reason:, scope: nil)
      kind = kind.to_s
      reason = reason.to_s.strip
      scope = scope.presence&.to_s
      return failure(base: "Only an owner can propose a change to the identity team.") unless can_propose?(by)
      return failure(kind: "is not a known change") unless IdentityGovernanceProposal::KINDS.include?(kind)
      return failure(base: "Choose a person by their Weave ID or email.") if subject.nil?
      return failure(reason: "is required") if reason.blank?

      role_key, = kind_role(kind)
      rule = kind_rule(kind)
      return failure(base: "This change does not need a proposal: #{RoleGrants.rule_text(*kind_role(kind))}") unless rule.proposal?

      unless RoleRegistry.valid_scope?(role_key, scope)
        return failure(scope: "must be one of: #{RoleRegistry.scopes_for(role_key).join(', ')}") if RoleRegistry.fetch(role_key).scopable?

        scope = nil
      end

      state_error = state_error(kind, subject, scope:)
      return failure(base: state_error) if state_error
      if IdentityGovernanceProposal.awaiting_approval.exists?(kind:, subject_id: subject.id, scope:)
        return failure(base: "A proposal for this change already waits for approval.")
      end

      required = rule.all_board? ? User.board_members.order(:id).pluck(:id) : []
      if rule.all_board? && required.size < MINIMUM_BOARD_FOR_KEY_HOLDERS
        return failure(base: "A key holder change needs at least #{MINIMUM_BOARD_FOR_KEY_HOLDERS} board members to approve it.")
      end

      proposal = nil
      with_whodunnit(by) do
        IdentityGovernanceProposal.transaction do
          proposal = IdentityGovernanceProposal.create!(
            kind:, subject:, scope:, proposed_by: by, reason:, required_approver_ids: required,
            expires_at: IdentityGovernanceSettings.proposal_expiry.from_now
          )
          record_event(:proposed, proposal, actor: by, reason:)
          ActiveRecord.after_all_transactions_commit { notify_approvers(proposal) }
        end
      end
      success(proposal)
    end

    def approve(proposal, by:)
      proposal.reload
      if proposal.expired_now?
        IdentityGovernanceProposal.transaction do
          proposal.lock!
          expire!(proposal) if proposal.expired_now?
        end
      end

      errors = {}
      with_whodunnit(by) do
        IdentityGovernanceProposal.transaction do
          lock_key_holders! if proposal.key_holder_change?
          proposal.lock!
          errors = approval_errors(proposal, by)
          raise ActiveRecord::Rollback if errors.any?

          proposal.approvals.create!(approver: by)
          record_event(:approved, proposal, actor: by)
          if complete?(proposal)
            errors = apply!(proposal, by)
            raise ActiveRecord::Rollback if errors.any?
          end
        end
      end
      errors.any? ? failure(errors, proposal) : success(proposal)
    end

    def reject(proposal, by:, reason:)
      reason = reason.to_s.strip
      return failure({ base: "Only a board member who may approve this proposal can reject it." }, proposal) unless proposal.open? && can_approve?(proposal, by)
      return failure({ reason: "is required" }, proposal) if reason.blank?

      close!(proposal, "rejected", by:, reason:)
      success(proposal)
    end

    def withdraw(proposal, by:)
      return failure({ base: "Only the proposer or an owner can withdraw a pending proposal." }, proposal) unless can_withdraw?(proposal, by)

      close!(proposal, "withdrawn", by:, reason: nil)
      success(proposal)
    end

    # Marks every pending proposal past its expiry (ExpireIdentityGovernanceProposalsJob).
    def expire_due!
      IdentityGovernanceProposal.due_to_expire.find_each do |proposal|
        IdentityGovernanceProposal.transaction do
          proposal.lock!
          expire!(proposal) if proposal.expired_now?
        end
      end
    end

    # -- Removal ---------------------------------------------------------

    def remove_member(subject, by:, reason:)
      reason = reason.to_s.strip
      return failure(base: "Only an owner or an identity team lead can remove a member of the identity team.") unless can_remove?(by, subject)
      return failure(reason: "is required") if reason.blank?

      event = nil
      errors = {}
      with_whodunnit(by) do
        User.transaction do
          lock_key_holders!
          lock_user_row!(subject)
          subject.reload_roles!
          was_key_holder = subject.identity_key_holder
          roles = { key_holder: subject.identity_key_holder, lead: subject.identity_lead }
          RoleGrants.revoke!(subject, "verifier", by:, reason:)
          IdentityGovernanceProposal.pending.where(subject:).find_each do |proposal|
            close!(proposal, "cancelled", by:, reason: "#{subject.full_name} was removed from the identity team.")
          end
          event = IdentityGovernanceEvent.record!(:member_removed, actor: by, subject:, reason:, was_key_holder: roles[:key_holder],
                                                                   was_lead: roles[:lead])
          ActiveRecord.after_all_transactions_commit do
            notify_board_of_removal(event)
            key_holders_changed(subject, :removed, nil, by) if was_key_holder
          end
        end
      end
      errors.any? ? failure(errors) : success(event)
    end

    # -- Bootstrap -------------------------------------------------------

    # True before the first bootstrap, while no member of the identity team is
    # verified. Only then can bootstrap! run. After the first run it stays
    # closed for ever: later changes go through proposals.
    def bootstrap_open? = !bootstrap_ran? && User.identity_team.none?(&:identity_verified?)

    def bootstrap_ran? = IdentityGovernanceEvent.exists?(kind: "bootstrap_member_added")

    # The one-time start of the identity team (docs/KYC_ROLLOUT.md). Nobody is
    # verified yet, so nobody can meet the verifier preconditions. An owner
    # adds the first verifiers at once. Each must be at least
    # verifier_minimum_age. Then they verify
    # each other in a circle: each person's verifier is the person before
    # them in the list, and the first person's verifier is the last person.
    #
    # Refuses after its first run, and once any member of the identity team
    # is verified.
    def bootstrap!(users, by:)
      users = Array(users).compact.uniq
      return failure(base: "Only an owner can run the bootstrap.") unless can_propose?(by)
      return failure(base: "The bootstrap is closed: it ran before. Use proposals.") if bootstrap_ran?
      return failure(base: "The bootstrap is closed: a member of the identity team is verified. Use proposals.") unless bootstrap_open?
      return failure(base: "Give at least two people, so each one is verified by another person.") if users.size < 2

      blocked = users.filter_map do |user|
        unmet = preconditions(user).reject { |check| check.key == :verified || check.met }
        "#{user.full_name}: #{unmet.map(&:detail).join(' ')}" if unmet.any?
      end
      return failure(base: "Not ready: #{blocked.join(' ')}") if blocked.any?

      plan = users.each_with_index.map { |user, index| [user, users[index - 1]] }
      with_whodunnit(by) do
        User.transaction do
          plan.each do |user, verifier|
            lock_user_row!(user)
            RoleGrants.grant!(user, "verifier", by:, reason: "Bootstrap of the identity team.") unless user.identity_team
            IdentityGovernanceEvent.record!(:bootstrap_member_added, actor: by, subject: user, verified_by_id: verifier.id,
                                                                     verified_by_p_id: verifier.p_id, circle: users.map(&:p_id))
          end
        end
      end
      success(plan)
    end

    # Where the bootstrap circle stands: each member, who verifies them, and
    # their verification status.
    def bootstrap_status
      IdentityGovernanceEvent.where(kind: "bootstrap_member_added").includes(:subject).order(:id).map do |event|
        verifier = User.find_by(id: event.data["verified_by_id"])
        user = event.subject
        { user:, verifier:, status: user&.verification_status, verified_by: user&.latest_verification&.verifier }
      end
    end

    # A member who joined in the bootstrap is not verified at first. Until
    # they are, they may record a call outcome only for the person after them
    # in the circle (VerificationFlow.decide asks). Returns the error, or nil.
    # Every other member was verified before they joined (see preconditions).
    def bootstrap_decision_error(by, member)
      return nil if by.nil? || by.identity_verified? || !bootstrap_member?(by)
      return nil if member && !member.identity_verified? && bootstrap_verifier_id(member) == by.id

      "You joined in the bootstrap and are not verified yet. You can only verify the person after you in the circle."
    end

    # -- Account deletion and the board ----------------------------------

    # The deletion pipeline calls this inside its transaction, before the
    # user row goes. A deleted identity team member leaves the team like a
    # removal: the open proposals about them close, the board is told, and a
    # key holder sends KEY_HOLDERS_CHANGED after the commit.
    def account_deleted!(user)
      return unless user.identity_team

      lock_key_holders!
      was_key_holder = user.identity_key_holder
      was_lead = user.identity_lead
      IdentityGovernanceProposal.pending.where(subject: user).find_each do |proposal|
        close!(proposal, "cancelled", by: nil, reason: "The account was deleted.")
      end
      event = IdentityGovernanceEvent.record!(:member_removed, actor: nil, subject: user, reason: "The account was deleted.",
                                                               was_key_holder:, was_lead:)
      RoleGrants.revoke!(user, "verifier", reason: "The account was deleted.")
      ActiveRecord.after_all_transactions_commit do
        notify_board_of_removal(event)
        key_holders_changed(user, :removed, nil, nil) if was_key_holder
      end
      event
    end

    # RoleGrants calls this in the transaction that granted or revoked the
    # board role. Only an owner makes the change (the board rule in
    # config/roles.yml). It is logged, and every board member before and
    # after the change gets an email.
    def board_changed!(user, by:)
      kind = user.is_board ? :board_member_added : :board_member_removed
      event = IdentityGovernanceEvent.record!(kind, actor: by, subject: user)
      recipients = User.board_members.or(User.where(id: user.id)).to_a
      ActiveRecord.after_all_transactions_commit do
        recipients.each do |member|
          next unless member.can_authenticate? && member.email.present?

          IdentityGovernanceMailer.board_changed(event, member).deliver_later
        end
      end
      event
    end

    private

    # The key ceremony needs the key holders, and no call can end before the
    # ceremony (pre-review seals the image to the key set). So until the first
    # key set exists, a member who joined in the bootstrap may become a key
    # holder before they are verified (config/roles.yml: verified_or_bootstrap).
    def key_holder_precondition(user)
      verified = preconditions(user).find { |check| check.key == :verified }.met
      waiver = !verified && bootstrap_key_holder_waiver?(user)
      Precondition.new(
        key: :verified_or_bootstrap, met: verified || waiver,
        detail: waiver ? "Not verified yet: joined in the bootstrap, before the first key ceremony." : "Not verified by another verifier."
      )
    end

    # Before the first key set, a bootstrap member counts as verified for the
    # key holder role (see preconditions).
    # A discarded or pending first set does not close it: only an activated
    # one does, so a failed first ceremony can still be redone.
    def bootstrap_key_holder_waiver?(user) = KeyCustodyKeySet.where.not(activated_at: nil).none? && bootstrap_member?(user)

    def bootstrap_member?(user) = IdentityGovernanceEvent.exists?(kind: "bootstrap_member_added", subject_id: user.id)

    # The planned verifier of a bootstrap member, from the newest bootstrap.
    def bootstrap_verifier_id(user)
      IdentityGovernanceEvent.where(kind: "bootstrap_member_added", subject_id: user.id).order(:id).last&.data&.dig("verified_by_id")
    end

    def lead?(user) = user.identity_team && user.identity_lead

    # A row lock on the user for the rest of the transaction. Not User#lock!:
    # that locks the account (it can't sign in, and its sessions and OAuth
    # tokens go).
    def lock_user_row!(user) = User.where(id: user.id).lock.pick(:id)

    def lock_key_holders!
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{KEY_HOLDER_LOCK})")
    end

    def state_error(kind, subject, scope: nil, stage: :proposal)
      flag_state_error(kind, subject, scope:) || precondition_error(kind, subject, stage)
    end

    # The preconditions that config/roles.yml names for the stage (:proposal
    # or :approval). Returns the error, or nil.
    def precondition_error(kind, subject, stage)
      rule = kind_rule(kind)
      names = stage == :proposal ? rule.preconditions_at_proposal : rule.preconditions_at_approval
      return nil if names.empty?

      keys = names.map { |name| PRECONDITION_KEYS.fetch(name) }
      checks = preconditions(subject)
      checks += [key_holder_precondition(subject)] if keys.include?(:verified_or_bootstrap)
      unmet = checks.select { |check| keys.include?(check.key) }.reject(&:met)
      return nil if unmet.empty?

      if kind == "add_member"
        "#{subject.full_name} can't join the identity team yet: #{unmet.map(&:detail).join(' ')}"
      elsif [[:verified], [:verified_or_bootstrap]].include?(unmet.map(&:key))
        "#{subject.full_name} must be verified (by another verifier) before this change."
      else
        "#{subject.full_name} can't get this role yet: #{unmet.map(&:detail).join(' ')}"
      end
    end

    def flag_state_error(kind, subject, scope: nil)
      case kind
      when "add_member"
        "#{subject.full_name} is already on the identity team." if subject.identity_team
      when "set_lead"
        if !subject.identity_team then "#{subject.full_name} must be on the identity team first."
        elsif subject.identity_lead then "#{subject.full_name} is already a lead."
        end
      when "clear_lead"
        "#{subject.full_name} is not a lead." unless subject.identity_lead
      when "add_key_holder"
        if !subject.identity_team then "#{subject.full_name} must be on the identity team first."
        elsif subject.identity_key_holder then "#{subject.full_name} is already a key holder."
        elsif User.identity_key_holders.count >= VerificationSettings.max_key_holders
          "There are already #{VerificationSettings.max_key_holders} key holders. Remove one first."
        end
      when "remove_key_holder"
        "#{subject.full_name} is not a key holder." unless subject.identity_key_holder
      when "add_patch_lead"
        "#{subject.full_name} is already the patch lead of #{scope}." if subject.has_role?("patch_lead", scope:)
      end
    end

    def approval_errors(proposal, by)
      return { base: "This proposal expired. The owner must propose it again." } if proposal.expired? || proposal.expired_now?
      return { base: "This proposal is #{proposal.status}." } unless proposal.pending?

      unless can_approve?(proposal, by)
        if proposal.all_board?
          return { base: "Only a board member from the time of the proposal who has not approved yet can approve a key holder change." }
        end

        return { base: "Only a board member who did not make the proposal, and who is not its subject, can approve it." }
      end

      subject = proposal.subject
      return { base: "The person of this proposal no longer exists." } if subject.nil?

      # A new verifier: the preconditions first, as before the roles table.
      if proposal.kind == "add_member"
        unmet = precondition_error(proposal.kind, subject, :approval)
        return { base: unmet } if unmet
      end

      state = state_error(proposal.kind, subject, scope: proposal.scope, stage: :approval)
      state ? { base: state } : {}
    end

    def complete?(proposal)
      proposal.all_board? ? proposal.missing_approver_ids.empty? : proposal.approvals.any?
    end

    # Applies an approved proposal. Returns errors, or {} on success.
    def apply!(proposal, by)
      subject = proposal.subject
      lock_user_row!(subject)
      subject.reload_roles!
      role_key, action = kind_role(proposal.kind)
      begin
        if action == :grant
          RoleGrants.grant!(subject, role_key, scope: proposal.scope, by:, reason: proposal.reason, proposal:)
        else
          RoleGrants.revoke!(subject, role_key, scope: proposal.scope, by:, reason: proposal.reason)
        end
      rescue RoleGrants::Error, ActiveRecord::RecordInvalid => error
        return { base: "Not applied: #{error.message}" }
      end

      proposal.update!(status: "applied", closed_at: Time.current, closed_by: by)
      record_event(:applied, proposal, actor: by)
      if proposal.key_holder_change?
        change = proposal.kind == "add_key_holder" ? :added : :removed
        ActiveRecord.after_all_transactions_commit { key_holders_changed(subject, change, proposal, by) }
      end
      {}
    end

    def close!(proposal, status, by:, reason:)
      proposal.update!(status:, closed_at: Time.current, closed_by: by, close_reason: reason)
      record_event(status, proposal, actor: by, reason:)
    end

    def expire!(proposal)
      proposal.update!(status: "expired", closed_at: Time.current)
      record_event(:expired, proposal, actor: nil)
    end

    def record_event(kind, proposal, actor:, **data)
      IdentityGovernanceEvent.record!(kind, actor:, subject: proposal.subject, proposal:, proposal_kind: proposal.kind,
                                            proposal_id: proposal.public_id, **{ proposal_scope: proposal.scope }.compact, **data.compact)
    end

    def key_holders_changed(user, change, proposal, actor)
      ActiveSupport::Notifications.instrument(
        KEY_HOLDERS_CHANGED,
        user:, change:, proposal:, actor:, holder_ids: User.identity_key_holders.order(:id).pluck(:id)
      )
    end

    def notify_approvers(proposal)
      eligible_approvers(proposal).each do |approver|
        next unless approver.can_authenticate? && approver.email.present?

        IdentityGovernanceMailer.approval_needed(proposal, approver).deliver_later
      end
    end

    def notify_board_of_removal(event)
      User.board_members.where.not(email: nil).find_each do |member|
        next unless member.can_authenticate?

        IdentityGovernanceMailer.member_removed(event, member).deliver_later
      end
    end

    # PaperTrail and the permanent log of privileged attributes both name the
    # actor (see PrivilegedChangeActor).
    def with_whodunnit(by, &block)
      PaperTrail.request(whodunnit: by&.id&.to_s) do
        by ? PrivilegedChangeActor.with(actor: by, &block) : yield
      end
    end

    def success(record) = Result.new(record:, errors: {})

    def failure(errors, record = nil) = Result.new(record:, errors:)

  end
end
