# frozen_string_literal: true

require "rails_helper"

RSpec.describe ThreadCount do
  let(:member) { create(:user, :verified) }
  let(:config) { described_class.config }

  def entry(*traits, **attributes)
    create(:thread_count_entry, *traits, user: member, **attributes)
  end

  describe ".score" do
    it "is zero with no entries" do
      expect(described_class.score(member)).to eq(0)
    end

    it "adds up the weights from the config" do
      entry(kind: "staff_vouch", level: "staff")
      entry(:moderation_case, level: "minor")

      expected = config.weight("staff_vouch", "staff") + config.weight("moderation_case", "minor")
      expect(described_class.score(member)).to eq(expected)
    end

    it "halves an entry after one half-life" do
      ThreadCount::Config.with(half_life_days: 100) do
        travel_to(100.days.ago) { entry(kind: "board_vouch", level: nil) }

        expect(described_class.score(member)).to be_within(0.01).of(config.weight("board_vouch") / 2)
      end
    end

    it "does not fade a kind whose half-life is null" do
      service = create(:service)
      ThreadCount::Config.with(half_life_days: 10, half_life_days_by_kind: { project_blacklisted: nil }) do
        travel_to(5.years.ago) do
          entry(kind: "project_blacklisted", level: nil, author: nil, recorded_by: nil, service:, project_ref: "p-1", reason: nil)
        end

        expect(described_class.score(member)).to eq(config.weight("project_blacklisted"))
      end
    end

    it "never fades a blacklist entry with the locked config, but fades other kinds" do
      service = create(:service)
      travel_to(9.years.ago) do
        entry(kind: "project_blacklisted", level: nil, author: nil, recorded_by: nil, service:, project_ref: "p-2", reason: nil)
        entry(kind: "project_denied", level: nil, author: nil, recorded_by: nil, service:, project_ref: "p-3", reason: nil)
      end

      lines = described_class.lines(member)
      blacklisted = lines.find { |line| line.entry.kind == "project_blacklisted" }
      denied = lines.find { |line| line.entry.kind == "project_denied" }
      expect(blacklisted.contribution).to eq(config.weight("project_blacklisted"))
      expect(denied.contribution).to be_within(0.01).of(config.weight("project_denied") / 8)
    end

    it "applies a changed weight to old entries, because the weight is not stored" do
      entry(kind: "board_vouch", level: nil)

      ThreadCount::Config.with(vouch_weights: { board: 99 }) do
        expect(described_class.score(member)).to eq(99)
      end
    end

    it "leaves out reversed entries and the reversal rows" do
      vouch = entry(kind: "board_vouch", level: nil)
      entry(kind: "reversal", level: nil, reverses: vouch)

      expect(described_class.score(member)).to eq(0)
    end

    it "counts only entries that existed at the given time" do
      travel_to(10.days.ago) { entry(kind: "board_vouch", level: nil) }
      entry(kind: "member_vouch", level: nil)

      expect(described_class.score(member, at: 5.days.ago)).to be < described_class.score(member)
    end

    it "counts an entry whose level was removed from the config as zero" do
      entry(:external_signal, level: "other_program")

      ThreadCount::Config.with(external_signal_weights: { other_program: nil }) do
        expect(described_class.score(member)).to eq(0)
      end
    end
  end

  describe ".lines" do
    it "lists every entry, newest first, with its weight and what it adds now" do
      old = travel_to(1.day.ago) { entry(kind: "board_vouch", level: nil) }
      new = entry(:moderation_case, level: "major")

      lines = described_class.lines(member)

      expect(lines.map(&:entry)).to eq([new, old])
      expect(lines.first.weight).to eq(config.weight("moderation_case", "major"))
    end
  end

  describe ".voucher_tier" do
    it "ranks board, then staff and admins, then members" do
      expect(described_class.voucher_tier(build(:user, :superadmin, is_board: true))).to eq("board")
      expect(described_class.voucher_tier(build(:user, :superadmin))).to eq("staff")
      expect(described_class.voucher_tier(build(:user, :owner))).to eq("staff")
      expect(described_class.voucher_tier(build(:user, :admin))).to eq("staff")
      expect(described_class.voucher_tier(build(:user, is_staff: true))).to eq("staff")
      expect(described_class.voucher_tier(build(:user))).to eq("member")
    end

    it "takes the senior roles from the config" do
      ThreadCount::Config.with(senior_staff_roles: ["admin"]) do
        expect(described_class.voucher_tier(build(:user, :admin))).to eq("senior_staff")
      end
    end
  end

  describe ".may_vouch?" do
    it "lets staff and board vouch at any score" do
      expect(described_class.may_vouch?(create(:user, is_staff: true))).to be(true)
      expect(described_class.may_vouch?(create(:user, is_board: true))).to be(true)
    end

    it "lets a member vouch only at or above the threshold" do
      ThreadCount::Config.with(member_vouch_threshold: 30, vouch_weights: { board: 30 }) do
        expect(described_class.may_vouch?(member)).to be(false)

        entry(kind: "board_vouch", level: nil)

        expect(described_class.may_vouch?(member)).to be(true)
      end
    end
  end
end
