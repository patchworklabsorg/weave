# frozen_string_literal: true

# Writes to the Thread Count ledger (see ThreadCount), with the rules for each
# kind of entry. Every method returns a Result: check #success? and #errors.
#
# Vouch rules:
# - The voucher's tier sets the kind and weight: board, senior staff, staff,
#   or member (see ThreadCount.voucher_tier).
# - A member may vouch only when their own score is at or above the threshold
#   in config/thread_count.yml.
# - Nobody vouches for themselves, and nobody records or reverses an entry
#   about themselves.
# - Staff record a vouch "on behalf of" only for a voucher with no admin
#   access (a board member or a member). A voucher with admin access records
#   their own vouch, so nobody can use another admin's name and weight.
# - One active vouch per voucher per member. To renew a faded vouch, pass
#   renew: true: the old vouch is reversed and a new one is added.
module ThreadCount
  module Ledger
    Result = Data.define(:entry, :errors) do
      def success? = errors.empty?
    end

    # Kinds a staff member may record by hand, besides vouches.
    MANUAL_KINDS = (%w[moderation_case external_signal] + ThreadCount::Entry::PROJECT_KINDS).freeze
    # Manual kinds that take score away. Only staff who outrank the member may
    # record them (see Admin::UserThreadCountEntriesController).
    DEDUCTION_KINDS = %w[moderation_case project_denied project_blacklisted].freeze
    PROJECT_OUTCOMES = %w[approved exceptional denied blacklisted].freeze

    class << self
      # voucher puts their name on the member. recorded_by is the staff member
      # who types it in: the voucher, or staff on behalf of a board member or
      # member who has no admin access.
      def vouch(subject:, voucher:, recorded_by:, reason:, evidence_url: nil, renew: false)
        return failure("You can't vouch for yourself.") if voucher == subject
        return failure("You can't record a vouch for your own account.") if recorded_by == subject
        if voucher != recorded_by && voucher.admin?
          return failure("#{voucher.full_name} has admin access and must record their own vouch.")
        end

        tier = ThreadCount.voucher_tier(voucher)
        kind, level = vouch_kind(tier)

        with_member_lock(subject) do
          return failure("#{voucher.full_name} can't vouch yet: their own Thread Count is below the threshold.") unless ThreadCount.may_vouch?(voucher)

          active = active_vouch(subject, voucher)
          return failure("#{voucher.full_name} already vouches for #{subject.full_name}. Renew the vouch instead.") if active && !renew

          entry = ThreadCount::Entry.new(user: subject, kind:, level:, author: voucher, recorded_by:, reason:, evidence_url:)
          return invalid(entry) unless entry.valid?

          ThreadCount::Entry.transaction do
            ThreadCount::Entry.create!(user: subject, kind: "reversal", reverses: active, author: recorded_by, recorded_by:, reason: "Renewed: #{reason}".truncate(ThreadCount::Entry::REASON_MAX_LENGTH)) if active
            entry.save!
          end
          Result.new(entry:, errors: [])
        end
      end

      # A moderation case, an external signal, or a project outcome that staff
      # record by hand. author is the staff member who stands behind it.
      def record(subject:, kind:, recorded_by:, reason:, level: nil, evidence_url: nil, evidence: nil)
        return failure("Use a vouch for that.") unless MANUAL_KINDS.include?(kind.to_s)
        return failure("You can't record an entry about your own account.") if recorded_by == subject

        entry = ThreadCount::Entry.new(user: subject, kind: kind.to_s, level: level.presence, author: recorded_by, recorded_by:,
                                       reason:, evidence_url:, evidence:)
        entry.save ? Result.new(entry:, errors: []) : invalid(entry)
      end

      # A project review outcome from a service (Krater or another). Safe to
      # retry: the same service, project and outcome are recorded once. An
      # exceptional project also gets the approval, so it adds more than a
      # plain approval.
      def record_project_event(subject:, service:, outcome:, project_ref:, reason: nil, evidence_url: nil)
        outcome = outcome.to_s
        return failure("Outcome must be one of: #{PROJECT_OUTCOMES.join(', ')}.") unless PROJECT_OUTCOMES.include?(outcome)
        return failure("Project ref can't be blank.") if project_ref.to_s.strip.empty?

        kinds = outcome == "exceptional" ? %w[project_approved project_exceptional] : ["project_#{outcome}"]
        entry = nil
        ThreadCount::Entry.transaction do
          kinds.each do |kind|
            entry = find_or_create_project_entry(subject:, service:, kind:, project_ref:, reason:, evidence_url:)
            raise ActiveRecord::Rollback unless entry.persisted?
          end
        end
        entry.persisted? ? Result.new(entry:, errors: []) : invalid(entry)
      end

      # Takes an entry back with a written reason. Superadmins may reverse any
      # entry. A voucher may withdraw their own vouch.
      def reverse(entry, by:, reason:)
        return failure("Only a superadmin can reverse this entry.") unless may_reverse?(entry, by)
        return failure("A reversal can't be reversed.") if entry.reversal?
        return failure("You can't reverse an entry about your own account.") if by == entry.user

        with_member_lock(entry.user) do
          return failure("This entry is already reversed.") if entry.reversed?

          reversal = ThreadCount::Entry.new(user: entry.user, kind: "reversal", reverses: entry, author: by, recorded_by: by, reason:)
          reversal.save ? Result.new(entry: reversal, errors: []) : invalid(reversal)
        end
      end

      def may_reverse?(entry, user)
        user.superadmin? || (entry.vouch? && entry.author_id.present? && entry.author_id == user.id)
      end

      # The voucher's vouch for the member that is not reversed, if any.
      def active_vouch(subject, voucher)
        ThreadCount::Entry.vouches.not_reversed.where(user: subject, author: voucher).order(:created_at).last
      end

      private

      # Serializes writes for one member, so two requests can't both pass the
      # one-active-vouch check. An advisory lock, not a row lock: User#lock!
      # locks the account, so User#with_lock must not be used here.
      def with_member_lock(user, &)
        ThreadCount::Entry.transaction do
          ThreadCount::Entry.connection.execute(
            ThreadCount::Entry.sanitize_sql_array(["SELECT pg_advisory_xact_lock(hashtext(?))", "thread_count:#{user.id}"])
          )
          yield
        end
      end

      def vouch_kind(tier)
        case tier
        when "board" then ["board_vouch", nil]
        when "member" then ["member_vouch", nil]
        else ["staff_vouch", tier]
        end
      end

      def find_or_create_project_entry(subject:, service:, kind:, project_ref:, reason:, evidence_url:)
        attributes = { service:, kind:, project_ref: project_ref.to_s.strip }
        existing = ThreadCount::Entry.find_by(attributes)
        return existing if existing && existing.user_id == subject.id
        return ThreadCount::Entry.new.tap { |entry| entry.errors.add(:project_ref, "is already recorded for another member") } if existing

        # A savepoint, so a concurrent duplicate does not abort the outer
        # transaction.
        ThreadCount::Entry.transaction(requires_new: true) do
          ThreadCount::Entry.create(**attributes, user: subject, reason:, evidence_url:)
        end
      rescue ActiveRecord::RecordNotUnique
        ThreadCount::Entry.find_by!(attributes)
      end

      def failure(message) = Result.new(entry: nil, errors: [message])

      def invalid(entry) = Result.new(entry:, errors: entry.errors.full_messages)

    end
  end
end
