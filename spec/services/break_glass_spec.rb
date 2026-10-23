# frozen_string_literal: true

require "rails_helper"

RSpec.describe BreakGlass do
  include ActiveJob::TestHelper

  let(:verification) { create(:verification, :verified) }
  let(:requester) { create(:user, :identity_team) }
  let!(:holders) { create_list(:user, 2, :key_holder) }
  let!(:lead) { create(:user, :identity_lead) }

  def member = verification.user

  def holder_a = holders.first

  def holder_b = holders.last

  def image = Rails.root.join("spec/fixtures/files/id_document.png").binread

  def granted_record
    record = described_class.request(verification, by: requester, reason: "Fraud report: compare the document.").record
    described_class.approve(record, by: holder_a)
    described_class.approve(record, by: holder_b)
    record.reload
  end

  describe ".request" do
    it "needs a written reason and asks each key holder" do
      result = nil
      expect { result = described_class.request(verification, by: requester, reason: "Fraud report: compare the document.") }
        .to have_enqueued_mail(BreakGlassMailer, :approval_needed).twice
      expect(result.record).to be_pending
      expect(verification.events.where(kind: "break_glass_requested")).to exist
    end

    it "refuses a request with no reason" do
      expect(described_class.request(verification, by: requester, reason: "")).not_to be_success
    end

    it "refuses a request from outside the identity team" do
      expect(described_class.request(verification, by: create(:user, :admin), reason: "Just curious about it")).not_to be_success
    end

    it "allows a request after a fail and after an escalation" do
      failed = create(:verification, :failed)
      escalated = create(:verification, :failed, escalated_at: 1.hour.ago)

      expect(described_class.request(failed, by: requester, reason: "Appeal: check the document again.")).to be_success
      expect(described_class.request(escalated, by: requester, reason: "Fraud review of the escalated case.")).to be_success
    end

    it "refuses a request before the decision, with a clear reason" do
      %i[pre_review awaiting_call call_scheduled].each do |state|
        attempt = create(:verification, state)
        result = described_class.request(attempt, by: requester, reason: "Fraud report: compare the document.")

        expect(result).not_to be_success
        expect(result.errors[:base]).to include("only for an attempt that passed, failed or was escalated")
      end
      expect(described_class.request(create(:verification), by: requester, reason: "Fraud report: compare it")).not_to be_success
      expect(BreakGlassRecord.count).to eq(0)
    end

    it "refuses a request when the image is purged" do
      verification.update!(document_purged_at: Time.current)

      expect(described_class.request(verification, by: requester, reason: "Fraud report: compare it")).not_to be_success
    end
  end

  describe "two-key approval" do
    let(:record) { described_class.request(verification, by: requester, reason: "Fraud report: compare the document.").record }

    it "grants after two different key holders approve" do
      described_class.approve(record, by: holder_a)
      expect(record.reload).to be_pending

      described_class.approve(record, by: holder_b)
      expect(record.reload).to be_granted
      expect(record.expires_at).to be_within(1.minute).of(VerificationSettings.break_glass_access.from_now)
    end

    it "does not count the same key holder twice" do
      described_class.approve(record, by: holder_a)

      expect(described_class.approve(record, by: holder_a)).to be(false)
      expect(record.reload).to be_pending
    end

    it "does not take an approval from a team member who holds no key" do
      expect(described_class.approve(record, by: lead)).to be(false)
    end

    it "refuses the lead verifier on one of the member's calls as an approver" do
      create(:verification, :failed, user: member, verifier: holder_a, created_at: 1.month.ago)

      expect(described_class.may_approve?(holder_a, record)).to be(false)
      expect(described_class.approve(record, by: holder_a)).to be(false)
      expect(described_class.deny(record, by: holder_a, reason: "Not needed for this report")).to be(false)
      expect(record.approvals).to be_empty
    end

    it "does not ask the member's lead verifier to approve" do
      create(:verification, :failed, user: member, verifier: holder_a, created_at: 1.month.ago)

      expect { described_class.request(verification, by: requester, reason: "Fraud report: compare the document.") }
        .to have_enqueued_mail(BreakGlassMailer, :approval_needed).once
    end

    it "lets a key holder deny with a reason" do
      expect(described_class.deny(record, by: holder_a, reason: "Not needed for this report")).to be(true)
      expect(record.reload).to be_denied
      expect(described_class.approve(record, by: holder_b)).to be(false)
    end
  end

  describe ".decrypt!" do
    it "returns the image, logs the decryption and enqueues the notices" do
      record = granted_record

      decrypted = described_class.decrypt!(record, viewer: requester, ip: "203.0.113.5")

      expect(decrypted.data).to eq(image)
      expect(record.decryptions.sole).to have_attributes(viewer: requester, ip: "203.0.113.5")
      expect(verification.events.where(kind: "document_decrypted")).to exist
      expect(DeliverBreakGlassNoticesJob).to have_been_enqueued
    end

    it "writes the notice ladder with the decryption" do
      record = granted_record

      described_class.decrypt!(record, viewer: requester)

      notices = record.decryptions.sole.notices.to_a
      expect(notices.map { |notice| [notice.recipient, notice.recipient_kind] })
        .to contain_exactly([holder_a, "key_holder"], [holder_b, "key_holder"], [lead, "lead"], [member, "member"])
      expect(notices.find(&:member?).due_at).to be_within(1.minute).of(VerificationSettings.member_notice_delay.from_now)
      expect(notices.reject(&:member?).map(&:due_at)).to all(be <= Time.current)
    end

    it "notifies only the other key holder when a key holder decrypts" do
      record = described_class.request(verification, by: holder_a, reason: "Fraud report: compare the document.").record
      described_class.approve(record, by: holder_a)
      described_class.approve(record, by: holder_b)

      described_class.decrypt!(record.reload, viewer: holder_a)

      kinds = record.decryptions.sole.notices.map { |notice| [notice.recipient, notice.recipient_kind] }
      expect(kinds).to contain_exactly([holder_b, "key_holder"], [lead, "lead"], [member, "member"])
    end

    it "logs every decryption" do
      record = granted_record

      2.times { described_class.decrypt!(record, viewer: requester) }

      expect(record.decryptions.count).to eq(2)
      expect(BreakGlassNotice.where(recipient: member).count).to eq(2)
    end

    it "refuses anybody but the requester" do
      expect { described_class.decrypt!(granted_record, viewer: holder_a) }.to raise_error(BreakGlass::NotPermitted)
      expect(BreakGlassDecryption.count).to eq(0)
    end

    it "refuses a requester who left the identity team after the grant" do
      record = granted_record
      requester.update!(identity_team: false)

      expect { described_class.decrypt!(record, viewer: requester) }.to raise_error(BreakGlass::NotPermitted)
      expect(BreakGlassDecryption.count).to eq(0)
    end

    it "refuses a request that is not granted" do
      record = described_class.request(verification, by: requester, reason: "Fraud report: compare the document.").record
      described_class.approve(record, by: holder_a)

      expect { described_class.decrypt!(record, viewer: requester) }.to raise_error(BreakGlass::NotPermitted)
    end

    it "refuses an expired grant" do
      record = granted_record

      travel(VerificationSettings.break_glass_access + 1.minute) do
        expect { described_class.decrypt!(record, viewer: requester) }.to raise_error(BreakGlass::NotPermitted)
      end
    end

    it "writes nothing and decrypts nothing when a notice can't be written" do
      record = granted_record
      allow(described_class).to receive(:create_notices!).and_raise(ActiveRecord::RecordNotSaved, "notice failed")

      expect { described_class.decrypt!(record, viewer: requester) }.to raise_error(ActiveRecord::RecordNotSaved)
      expect(BreakGlassDecryption.count).to eq(0)
      expect(DeliverBreakGlassNoticesJob).not_to have_been_enqueued
    end
  end

  describe "the member notice delay" do
    let(:notice) do
      described_class.decrypt!(granted_record, viewer: requester)
      BreakGlassNotice.find_by!(recipient_kind: "member")
    end

    def second = lead

    def due_later = travel(VerificationSettings.member_notice_delay + 1.minute) { BreakGlassNotice.due.to_a }

    it "takes the request with a reason and tells the lead, but holds nothing before a sign-off" do
      expect { described_class.delay_member_notice(notice, by: requester, reason: "Active fraud case 12") }
        .to have_enqueued_mail(BreakGlassMailer, :notice_delayed).with(notice, lead)
      expect(notice.reload).to be_delayed
      expect(notice).not_to be_delay_signed_off
      expect(due_later).to include(notice)
    end

    it "holds the notice after the identity team lead signs off" do
      described_class.delay_member_notice(notice, by: requester, reason: "Active fraud case 12")

      expect(described_class.sign_off_delay(notice, by: second)).to be(true)

      expect(notice.reload).to have_attributes(delay_signed_off_by: second)
      expect(due_later).not_to include(notice)
      expect(verification.events.where(kind: "member_notice_delay_signed_off", actor: second)).to exist
    end

    it "does not take a sign-off from the person who asked for the delay" do
      described_class.delay_member_notice(notice, by: requester, reason: "Active fraud case 12")

      expect(described_class.sign_off_delay(notice, by: requester)).to be(false)
      expect(described_class.sign_off_delay(notice, by: create(:user, :admin))).to be(false)
      expect(notice.reload).not_to be_delay_signed_off
    end

    it "takes a sign-off from an owner who is not on the identity team" do
      described_class.delay_member_notice(notice, by: requester, reason: "Active fraud case 12")
      owner = create(:user, :owner)

      expect(described_class.sign_off_delay(notice, by: owner)).to be(true)
      expect(notice.reload).to have_attributes(delay_signed_off_by: owner)
    end

    it "does not take a sign-off from another identity team member or a key holder" do
      described_class.delay_member_notice(notice, by: requester, reason: "Active fraud case 12")

      expect(described_class.sign_off_delay(notice, by: create(:user, :identity_team))).to be(false)
      expect(described_class.sign_off_delay(notice, by: holder_a)).to be(false)
      expect(notice.reload).not_to be_delay_signed_off
    end

    it "does not take a sign-off from a lead or an owner who asked for the access" do
      requester.update!(identity_lead: true, role: :owner)
      described_class.delay_member_notice(notice, by: create(:user, :identity_team), reason: "Active fraud case 12")

      expect(described_class.sign_off_delay(notice, by: requester)).to be(false)
      expect(described_class.sign_off_delay(notice, by: lead)).to be(true)
    end

    it "does not take a sign-off from a lead who asked for the delay" do
      described_class.delay_member_notice(notice, by: lead, reason: "Active fraud case 12")

      expect(described_class.sign_off_delay(notice, by: lead)).to be(false)
      expect(described_class.sign_off_delay(notice, by: create(:user, :owner))).to be(true)
    end

    it "holds the notice for at most the configured maximum" do
      described_class.delay_member_notice(notice, by: requester, reason: "Active fraud case 12")
      described_class.sign_off_delay(notice, by: second)

      travel(VerificationSettings.member_notice_delay + VerificationSettings.max_fraud_delay - 1.hour) do
        expect(BreakGlassNotice.due).not_to include(notice)
      end
      travel(VerificationSettings.member_notice_delay + VerificationSettings.max_fraud_delay + 1.minute) do
        expect(BreakGlassNotice.due).to include(notice)
      end
    end

    it "needs a reason" do
      expect(described_class.delay_member_notice(notice, by: requester, reason: "")).to be(false)
    end

    it "can't delay a notice to staff" do
      staff_notice = BreakGlassNotice.find_by!(recipient_kind: "lead", break_glass_decryption: notice.break_glass_decryption)

      expect(described_class.delay_member_notice(staff_notice, by: requester, reason: "Active fraud case 12")).to be(false)
    end

    it "sends the notice once the delay is lifted" do
      described_class.delay_member_notice(notice, by: requester, reason: "Active fraud case 12")
      described_class.sign_off_delay(notice, by: second)

      described_class.lift_delay(notice, by: requester)

      travel(VerificationSettings.member_notice_delay + 1.minute) do
        expect(BreakGlassNotice.due).to include(notice)
      end
    end
  end
end
