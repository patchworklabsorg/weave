# frozen_string_literal: true

# Thread Count (TC): the internal trust score of a member (proposal v0.8,
# section 05).
#
# Every trust signal is a row in an append-only ledger (ThreadCount::Entry):
# vouches, project review outcomes, moderation cases and external signals.
# The score is the sum of the entries, each faded by its age. It is computed
# from the ledger each time and never stored, so a change to the weights in
# config/thread_count.yml applies to the whole history.
#
# Strictly internal. The score never goes to the member, to an OAuth claim,
# to the directory API, to a webhook or to a serializer
# (spec/services/thread_count_internal_spec.rb guards this). Admins see the
# score. Only superadmins and owners see what it is made of.
#
# Writes go through ThreadCount::Ledger, which holds the vouch rules.
module ThreadCount
  # One entry, whether a later reversal cancels it, and what it adds to the
  # score now.
  Line = Data.define(:entry, :reversed, :weight, :contribution) do
    def reversed? = reversed
  end

  class << self
    def config = Config.current

    # The score now (or at `at`), from the entries that are not reversed.
    def score(user, at: Time.current)
      lines(user, at:).sum(&:contribution).round(2)
    end

    # Every entry of the user, newest first, with its weight and what it adds
    # now. Reversed entries and reversal rows add nothing. preload: true loads
    # the people and services for the composition table.
    def lines(user, at: Time.current, preload: false)
      entries = user_entries(user, preload:).where(created_at: ..at).to_a
      reversed_ids = entries.filter_map(&:reverses_id).to_set
      entries.map do |entry|
        reversed = reversed_ids.include?(entry.id)
        if entry.reversal? || reversed
          Line.new(entry:, reversed:, weight: 0, contribution: 0.0)
        else
          weight = weight_of(entry)
          Line.new(entry:, reversed:, weight:, contribution: weight * decay(entry, at:))
        end
      end
    end

    # The factor from 1.0 (new) toward 0.0 for the entry's age.
    def decay(entry, at: Time.current)
      half_life = config.half_life_days(entry.kind)
      return 1.0 if half_life.nil?

      age_days = [(at - entry.created_at) / 1.day, 0].max
      0.5**(age_days / half_life)
    end

    # Who the person is when they vouch: "board", "senior_staff", "staff" or
    # "member". Board wins over staff roles.
    def voucher_tier(user)
      if user.is_board
        "board"
      elsif config.senior_staff_roles.include?(user.role.to_s)
        "senior_staff"
      elsif user.is_staff || user.admin?
        "staff"
      else
        "member"
      end
    end

    # A member may vouch only with a score at or above the threshold. Staff
    # and board may always vouch.
    def may_vouch?(user)
      voucher_tier(user) != "member" || score(user) >= config.member_vouch_threshold
    end

    private

    # A level removed from the config adds nothing, and is logged, so one old
    # entry can't break the page.
    def weight_of(entry)
      config.weight(entry.kind, entry.level)
    rescue Config::UnknownWeight => e
      Rails.logger.warn("ThreadCount: #{e.message} (entry #{entry.id})")
      0.0
    end

    def user_entries(user, preload:)
      entries = ThreadCount::Entry.where(user:).order(created_at: :desc, id: :desc)
      preload ? entries.includes(:author, :recorded_by, :service) : entries
    end

  end
end
