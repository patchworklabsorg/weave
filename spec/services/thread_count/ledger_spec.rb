# frozen_string_literal: true

require "rails_helper"

RSpec.describe ThreadCount::Ledger do
  let(:member) { create(:user, :verified) }
  let(:staff) { create(:user, :admin, :verified, is_staff: true) }
  let(:superadmin) { create(:user, :superadmin, :verified) }
  let(:board) { create(:user, :verified, is_board: true) }

  def vouch(voucher, recorded_by: voucher, **options)
    described_class.vouch(subject: member, voucher:, recorded_by:, reason: "Worked with them for a year.", **options)
  end

  describe ".vouch" do
    it "records a staff vouch with the voucher's tier" do
      result = vouch(staff)

      expect(result).to be_success
      expect(result.entry).to have_attributes(kind: "staff_vouch", level: "staff", author: staff, recorded_by: staff)
    end

    it "records a senior staff vouch for a configured senior role" do
      ThreadCount::Config.with(senior_staff_roles: ["superadmin"]) do
        expect(vouch(superadmin).entry).to have_attributes(kind: "staff_vouch", level: "senior_staff")
      end
    end

    it "records a board vouch, typed in by staff on the board member's behalf" do
      result = vouch(board, recorded_by: staff)

      expect(result.entry).to have_attributes(kind: "board_vouch", level: nil, author: board, recorded_by: staff)
    end

    it "uses the locked vouch weights: board 30, staff 15, member 5" do
      config = ThreadCount.config

      expect([config.weight("board_vouch"), config.weight("staff_vouch", "staff"), config.weight("member_vouch")])
        .to eq([30, 15, 5])
      expect(config.weight("staff_vouch", "senior_staff")).to eq(config.weight("staff_vouch", "staff"))
    end

    it "refuses a vouch on behalf of a voucher with admin access" do
      result = vouch(superadmin, recorded_by: staff)

      expect(result).not_to be_success
      expect(result.errors.first).to include("must record their own vouch")
      expect(ThreadCount::Entry.count).to eq(0)
    end

    it "lets staff record a vouch for a staff member with no admin access" do
      result = vouch(create(:user, :verified, is_staff: true), recorded_by: staff)

      expect(result.entry).to have_attributes(kind: "staff_vouch", level: "staff", recorded_by: staff)
    end

    it "refuses a member below the threshold" do
      result = vouch(create(:user, :verified), recorded_by: staff)

      expect(result).not_to be_success
      expect(result.errors.first).to include("below the threshold")
    end

    it "lets a member at the threshold vouch, with the member weight" do
      voucher = create(:user, :verified)
      ThreadCount::Config.with(member_vouch_threshold: 10, vouch_weights: { board: 10 }) do
        create(:thread_count_entry, user: voucher, kind: "board_vouch", level: nil)

        result = vouch(voucher, recorded_by: staff)

        expect(result.entry).to have_attributes(kind: "member_vouch", author: voucher)
      end
    end

    it "refuses a self-vouch" do
      result = described_class.vouch(subject: staff, voucher: staff, recorded_by: superadmin, reason: "Me")

      expect(result.errors).to eq(["You can't vouch for yourself."])
    end

    it "refuses a vouch that the member records for their own account" do
      result = described_class.vouch(subject: staff, voucher: board, recorded_by: staff, reason: "On behalf")

      expect(result).not_to be_success
    end

    it "needs a written reason" do
      result = described_class.vouch(subject: member, voucher: staff, recorded_by: staff, reason: " ")

      expect(result.errors).to include("Reason can't be blank")
    end

    it "keeps one active vouch per voucher per member" do
      vouch(staff)

      result = vouch(staff)

      expect(result).not_to be_success
      expect(result.errors.first).to include("already vouches")
      expect(ThreadCount::Entry.vouches.count).to eq(1)
    end

    it "lets another voucher vouch for the same member" do
      vouch(staff)

      expect(vouch(board, recorded_by: staff)).to be_success
    end

    it "renews a vouch: the old one is reversed and a new one starts fresh" do
      old = travel_to(2.years.ago) { vouch(staff).entry }

      result = vouch(staff, renew: true)

      expect(result).to be_success
      expect(old.reload).to be_reversed
      expect(described_class.active_vouch(member, staff)).to eq(result.entry)
      expect(ThreadCount.score(member)).to eq(ThreadCount.config.weight("staff_vouch", "staff"))
    end

    it "allows a new vouch after the old one is withdrawn" do
      old = vouch(staff).entry
      described_class.reverse(old, by: staff, reason: "Changed my mind")

      expect(vouch(staff)).to be_success
    end
  end

  describe ".record" do
    it "records a moderation case with the recorder as author" do
      result = described_class.record(subject: member, kind: "moderation_case", level: "major", recorded_by: staff,
                                      reason: "Harassment report, case 12", evidence_url: "https://example.org/case/12")

      expect(result.entry).to have_attributes(kind: "moderation_case", level: "major", author: staff, recorded_by: staff)
      expect(ThreadCount.score(member)).to be < 0
    end

    it "records an external signal such as GitHub Student" do
      result = described_class.record(subject: member, kind: "external_signal", level: "github_student", recorded_by: staff,
                                      reason: "Showed the GitHub Student pack page")

      expect(result).to be_success
      expect(ThreadCount.score(member)).to be > 0
    end

    it "refuses vouches and reversals, which have their own rules" do
      %w[staff_vouch board_vouch member_vouch reversal].each do |kind|
        expect(described_class.record(subject: member, kind:, recorded_by: staff, reason: "x")).not_to be_success
      end
    end

    it "refuses an entry about the recorder's own account" do
      result = described_class.record(subject: staff, kind: "external_signal", level: "github_student", recorded_by: staff, reason: "x")

      expect(result).not_to be_success
    end

    it "needs a written reason" do
      result = described_class.record(subject: member, kind: "moderation_case", level: "minor", recorded_by: staff, reason: "")

      expect(result.errors).to include("Reason can't be blank")
    end
  end

  describe ".record_project_event" do
    let(:service) { create(:service, name: "Krater") }

    def event(outcome, project_ref: "proj-1", subject: member)
      described_class.record_project_event(subject:, service:, outcome:, project_ref:)
    end

    it "adds score for an approval" do
      expect(event("approved").entry).to have_attributes(kind: "project_approved", service:, project_ref: "proj-1", author: nil)
      expect(ThreadCount.score(member)).to eq(ThreadCount.config.weight("project_approved"))
    end

    it "adds more for an exceptional project: the approval and the extra" do
      event("exceptional")

      expect(ThreadCount::Entry.pluck(:kind)).to contain_exactly("project_approved", "project_exceptional")
      expect(ThreadCount.score(member)).to be > ThreadCount.config.weight("project_approved")
    end

    it "does not double the approval when an approved project is later marked exceptional" do
      event("approved")
      event("exceptional")

      expect(ThreadCount::Entry.where(kind: "project_approved").count).to eq(1)
    end

    it "removes score for a denied or blacklisted project" do
      event("denied", project_ref: "a")
      event("blacklisted", project_ref: "b")

      expect(ThreadCount.score(member)).to eq(ThreadCount.config.weight("project_denied") + ThreadCount.config.weight("project_blacklisted"))
      expect(ThreadCount.score(member)).to be < 0
    end

    it "records a retried event once" do
      first = event("approved")
      second = event("approved")

      expect(second).to be_success
      expect(second.entry).to eq(first.entry)
      expect(ThreadCount::Entry.count).to eq(1)
    end

    it "refuses an unknown outcome" do
      expect(event("cool").errors.first).to include("Outcome must be one of")
    end

    it "refuses a blank project ref" do
      expect(event("approved", project_ref: " ")).not_to be_success
    end

    it "refuses a project ref already recorded for another member" do
      event("approved")

      expect(event("approved", subject: create(:user, :verified))).not_to be_success
    end
  end

  describe ".reverse" do
    let(:entry) { create(:thread_count_entry, user: member, author: staff) }

    it "lets a superadmin reverse any entry, with a reason" do
      result = described_class.reverse(entry, by: superadmin, reason: "Recorded on the wrong member")

      expect(result.entry).to have_attributes(kind: "reversal", reverses: entry, author: superadmin)
      expect(ThreadCount.score(member)).to eq(0)
    end

    it "lets a voucher withdraw their own vouch" do
      expect(described_class.reverse(entry, by: staff, reason: "Withdrawn")).to be_success
    end

    it "does not let an admin reverse someone else's entry" do
      other = create(:user, :admin, :verified)

      expect(described_class.reverse(entry, by: other, reason: "No")).not_to be_success
    end

    it "does not let a voucher reverse a moderation case they recorded" do
      moderation = create(:thread_count_entry, :moderation_case, user: member, author: staff)

      expect(described_class.reverse(moderation, by: staff, reason: "Oops")).not_to be_success
    end

    it "reverses an entry once" do
      described_class.reverse(entry, by: superadmin, reason: "One")

      expect(described_class.reverse(entry, by: superadmin, reason: "Two").errors).to eq(["This entry is already reversed."])
    end

    it "does not reverse a reversal" do
      reversal = described_class.reverse(entry, by: superadmin, reason: "One").entry

      expect(described_class.reverse(reversal, by: superadmin, reason: "Two")).not_to be_success
    end

    it "does not let anyone reverse an entry about their own account" do
      moderation = create(:thread_count_entry, :moderation_case, user: superadmin, author: staff)

      result = described_class.reverse(moderation, by: superadmin, reason: "Not fair")

      expect(result.errors).to eq(["You can't reverse an entry about your own account."])
      expect(moderation).not_to be_reversed
    end

    it "needs a reason" do
      expect(described_class.reverse(entry, by: superadmin, reason: "")).not_to be_success
    end
  end
end
