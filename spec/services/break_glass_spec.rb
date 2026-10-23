# frozen_string_literal: true

require "rails_helper"

RSpec.describe BreakGlass do
  include ActiveJob::TestHelper

  let!(:custody) { setup_key_custody }
  let(:verification) { seal!(create(:verification, :verified)) }
  let(:requester) { create(:user, :identity_team) }
  let!(:lead) { create(:user, :identity_lead) }

  def keys = custody.last

  def holders = keys.keys

  def member = verification.user

  def holder_a = holders[0]

  def holder_b = holders[1]

  def holder_c = holders[2]

  def key_of(holder, index = 0) = keys[holder][index]

  def image = Rails.root.join("spec/fixtures/files/id_document.png").binread

  def ask(for_verification = verification, by: requester)
    described_class.request(for_verification, by:, reason: "Fraud report: compare the document.", requester_public_key: browser_public_key(by)).record
  end

  def approve(record, holder, key = key_of(holder), **)
    approve_with_key(record, holder, key, **)
  end

  def granted_record
    record = ask
    approve(record, holder_a)
    approve(record, holder_b)
    record.reload
  end

  # Granted, and opened by the requester's browser.
  def opened_record
    record = granted_record
    described_class.open!(record, by: record.requested_by)
    record.reload
  end

  describe ".request" do
    it "needs a written reason and asks each key holder" do
      result = nil
      expect { result = described_class.request(verification, by: requester, reason: "Fraud report: compare the document.", requester_public_key: browser_public_key(requester)) }
        .to have_enqueued_mail(BreakGlassMailer, :approval_needed).exactly(3).times
      expect(result.record).to be_pending
      expect(verification.events.where(kind: "break_glass_requested")).to exist
    end

    it "needs the public key of the requester's one-time browser key" do
      result = described_class.request(verification, by: requester, reason: "Fraud report: compare the document.")
      expect(result).not_to be_success
      expect(result.errors[:requester_public_key]).to include("one-time key")

      bad = described_class.request(verification, by: requester, reason: "Fraud report: compare the document.",
                                                  requester_public_key: Base64.strict_encode64("short"))
      expect(bad).not_to be_success
    end

    it "refuses a request with no reason" do
      expect(described_class.request(verification, by: requester, reason: "", requester_public_key: browser_public_key(requester))).not_to be_success
    end

    it "refuses a request from outside the identity team" do
      expect(described_class.request(verification, by: create(:user, :admin), reason: "Just curious about it")).not_to be_success
    end

    it "allows a request after a fail and after an escalation" do
      failed = seal!(create(:verification, :failed))
      escalated = seal!(create(:verification, :failed, escalated_at: 1.hour.ago))

      expect(described_class.request(failed, by: requester, reason: "Appeal: check the document again.", requester_public_key: browser_public_key(requester))).to be_success
      expect(described_class.request(escalated, by: requester, reason: "Fraud review of the escalated case.", requester_public_key: browser_public_key(requester))).to be_success
    end

    it "refuses a request before the decision, with a clear reason" do
      %i[pre_review awaiting_call call_scheduled].each do |state|
        attempt = create(:verification, state)
        result = described_class.request(attempt, by: requester, reason: "Fraud report: compare the document.", requester_public_key: browser_public_key(requester))

        expect(result).not_to be_success
        expect(result.errors[:base]).to include("only for an attempt that passed, failed or was escalated")
      end
      expect(described_class.request(create(:verification), by: requester, reason: "Fraud report: compare it")).not_to be_success
      expect(BreakGlassRecord.count).to eq(0)
    end

    it "refuses a request when the image is purged" do
      verification.update!(document_purged_at: Time.current)

      expect(described_class.request(verification, by: requester, reason: "Fraud report: compare it", requester_public_key: browser_public_key(requester))).not_to be_success
    end

    it "refuses a decided attempt whose image is not sealed" do
      unsealed = create(:verification, :verified)

      result = described_class.request(unsealed, by: requester, reason: "Fraud report: compare it", requester_public_key: browser_public_key(requester))

      expect(result).not_to be_success
      expect(result.errors[:base]).to include("no sealed image")
    end
  end

  describe "approval with a share and a hardware key" do
    let(:record) { ask }

    it "grants after any 2 of the 3 key holders give their shares, and the image opens" do
      holders.combination(2).each do |pair|
        attempt = seal!(create(:verification, :verified))
        subset_record = ask(attempt)

        first = approve(subset_record, pair[0])
        expect(first).to have_attributes(error: nil, granted: false)
        expect(subset_record.reload).to be_pending

        second = approve(subset_record, pair[1])
        expect(second).to have_attributes(error: nil, granted: true)
        expect(subset_record.reload).to be_granted
        expect(subset_record.key_set).to eq(custody.first.key_set)
        expect(open_in_browser(described_class.open!(subset_record, by: requester), requester)).to eq(image)
      end
    end

    it "opens with either of a holder's two keys" do
      approve(record, holder_a, key_of(holder_a, 1))
      approve(record, holder_c, key_of(holder_c, 1))

      expect(record.reload).to be_granted
    end

    it "refuses to open with one share" do
      result = approve(record, holder_a)

      expect(result.granted).to be(false)
      expect(record.reload).to be_pending
      expect(record.handoff_sealed_key).to be_nil
      expect(BreakGlassDecryption.count).to eq(0)
    end

    it "keeps no data key and no access window: to see the image again, ask again" do
      record = granted_record

      expect(BreakGlassRecord.column_names.grep(/data_key|wiped/)).to be_empty
      expect(record.status).to eq(:ready)
      described_class.open!(record, by: requester)
      expect(record.reload.status).to eq(:opened)
      expect(approve(record, holder_c).error).to include("not pending")
      expect(described_class).not_to respond_to(:decrypt!)
      expect(VerificationSettings).not_to respond_to(:break_glass_access)
    end

    it "deletes the waiting shares after the unlock" do
      approve(record, holder_a)
      expect(KeyCustody::PendingShares.size).to eq(1)

      approve(record, holder_b)

      expect(KeyCustodyPendingShare.count).to eq(0)
    end

    it "lets the requester approve their own request when they are a key holder" do
      own = ask(by: holder_a)

      expect(approve(own, holder_a)).to have_attributes(error: nil, granted: false)
      expect(approve(own, holder_b)).to have_attributes(error: nil, granted: true)

      expect(open_in_browser(described_class.open!(own, by: holder_a), holder_a)).to eq(image)
      expect(own.reload.approvers).to contain_exactly(holder_a, holder_b)
    end

    it "does not count the same key holder twice" do
      approve(record, holder_a)

      expect(approve(record, holder_a, key_of(holder_a, 1)).error).to include("already approved")
      expect(record.reload).to be_pending
    end

    it "does not take an approval from a team member who holds no key" do
      expect(described_class.may_approve?(lead, record)).to be(false)
      expect(described_class.approval_options(record, by: lead)).to be_nil
    end

    it "refuses the lead verifier on one of the member's calls as an approver" do
      create(:verification, :failed, user: member, verifier: holder_a, created_at: 1.month.ago)

      expect(described_class.may_approve?(holder_a, record)).to be(false)
      expect(described_class.approval_options(record, by: holder_a)).to be_nil
      expect(approve(record, holder_a).error).to include("may approve")
      expect(described_class.deny(record, by: holder_a, reason: "Not needed for this report")).to be(false)
      expect(record.approvals).to be_empty
      expect(KeyCustody::PendingShares.size).to eq(0)
    end

    it "does not ask the member's lead verifier to approve" do
      create(:verification, :failed, user: member, verifier: holder_a, created_at: 1.month.ago)

      expect { ask }.to have_enqueued_mail(BreakGlassMailer, :approval_needed).twice
    end

    it "refuses a hardware key of another holder" do
      result = approve(record, holder_a, key_of(holder_b), share: open_share(key_of(holder_a), custody.first.key_set))

      expect(result.error).to include("not one that can open this share")
      expect(record.approvals).to be_empty
    end

    it "refuses a revoked hardware key" do
      share = open_share(key_of(holder_a), custody.first.key_set)
      KeyCustody::Enrollment.revoke!(key_of(holder_a).record, by: holder_a, reason: "Lost on the train")

      result = approve(record, holder_a, key_of(holder_a), share:)

      expect(result.error).to include("not one that can open this share")
    end

    it "refuses the share of another holder" do
      other_share = open_share(key_of(holder_b), custody.first.key_set)

      result = approve(record, holder_a, key_of(holder_a), share: other_share)

      expect(result.error).to include("not your share")
      expect(KeyCustody::PendingShares.size).to eq(0)
    end

    it "refuses a wrong share" do
      expect(approve(record, holder_a, key_of(holder_a), share: SecureRandom.random_bytes(33)).error).to include("not your share")
      expect(approve(record, holder_a, key_of(holder_a), share: "short").error).to include("not valid")
    end

    it "refuses a replayed assertion" do
      challenge = KeyCustody::Assertions.issue!(user: holder_a, purpose: "break_glass", subject: record.public_id)
      credential = key_of(holder_a).assert(challenge.challenge)
      share = b64url(open_share(key_of(holder_a), custody.first.key_set))
      expect(described_class.approve(record, by: holder_a, credential:, share:)).to be_success
      KeyCustody::PendingShares.clear!

      replay = described_class.approve(record, by: holder_a, credential:, share:)

      expect(replay.error).to include("already used")
    end

    it "refuses an assertion made for another request" do
      other = ask(seal!(create(:verification, :verified)))
      challenge = KeyCustody::Assertions.issue!(user: holder_a, purpose: "break_glass", subject: other.public_id)
      share = b64url(open_share(key_of(holder_a), custody.first.key_set))

      result = described_class.approve(record, by: holder_a, credential: key_of(holder_a).assert(challenge.challenge), share:)

      expect(result.error).to include("unknown, expired or already used")
    end

    it "refuses an assertion without the key's PIN (user verification)" do
      challenge = KeyCustody::Assertions.issue!(user: holder_a, purpose: "break_glass", subject: record.public_id)
      share = b64url(open_share(key_of(holder_a), custody.first.key_set))

      result = described_class.approve(record, by: holder_a, credential: key_of(holder_a).assert(challenge.challenge, user_verified: false),
                                               share:)

      expect(result.error).to include("not valid")
    end

    it "binds the challenge to the request id" do
      options = described_class.approval_options(record, by: holder_a)

      expect(KeyCustody::Assertions.decode(options[:request][:challenge])).to start_with("weave:break_glass:#{record.public_id}:")
      expect(options[:request][:allowCredentials].pluck(:id)).to match_array(keys[holder_a].map(&:external_id))
      expect(options[:wrapped].keys).to match_array(keys[holder_a].map(&:external_id))
    end

    it "lapses an approval whose share left memory, and takes the share again" do
      approve(record, holder_a)

      travel(VerificationSettings.pending_share_ttl + 1.minute) do
        expect(approve(record, holder_b)).to have_attributes(error: nil, granted: false)
        expect(record.approvals.find_by(approver: holder_a)).to be_lapsed
        expect(verification.events.where(kind: "break_glass_approval_lapsed", actor: holder_a)).to exist

        expect(approve(record, holder_a)).to have_attributes(error: nil, granted: true)
      end
      expect(record.reload).to be_granted
      expect(record.approvers).to contain_exactly(holder_a, holder_b)
    end

    it "drops the waiting share of an approver who is no longer a key holder at the grant" do
      approve(record, holder_a)
      holder_a.update!(identity_key_holder: false)

      expect(approve(record, holder_b)).to have_attributes(error: nil, granted: false)
      expect(record.approvals.find_by(approver: holder_a)).to be_lapsed
      expect(described_class.pending_share_holder_ids(record)).to contain_exactly(holder_b.id)
      expect(verification.events.where(kind: "break_glass_approval_lapsed", actor: holder_a)).to exist

      expect(approve(record, holder_c)).to have_attributes(error: nil, granted: true)
      expect(record.reload.approvers).to contain_exactly(holder_b, holder_c)
    end

    it "drops the waiting share of an approver who became the member's lead verifier before the grant" do
      approve(record, holder_a)
      create(:verification, :verified, user: member, verifier: holder_a)

      expect(approve(record, holder_b)).to have_attributes(error: nil, granted: false)
      expect(record.reload).to be_pending
      expect(record.approvals.find_by(approver: holder_a)).to be_lapsed
    end

    it "logs a failed unlock, tells the board and rolls the approval back" do
      board = create(:user, is_board: true)
      approve(record, holder_a)
      allow(KeyCustody::Shamir).to receive(:combine).and_return(SecureRandom.random_bytes(32))

      result = nil
      expect { result = approve(record, holder_b) }.to have_enqueued_mail(KeyCustodyMailer, :event).with(anything, board)

      expect(result.error).to include("did not unlock")
      expect(record.reload).to be_pending
      expect(record.approvals.find_by(approver: holder_b)).to be_nil
      expect(KeyCustodyEvent.where(kind: "unlock_failed")).to exist
    end

    it "lets a key holder deny with a reason, and drops the waiting shares" do
      approve(record, holder_a)

      expect(described_class.deny(record, by: holder_b, reason: "Not needed for this report")).to be(true)
      expect(record.reload).to be_denied
      expect(KeyCustody::PendingShares.size).to eq(0)
      expect(approve(record, holder_c).error).to include("not pending")
    end
  end

  describe "a share is never stored in plain form" do
    def encodings(shares) = shares.flat_map { |share| [b64url(share), share.unpack1("H*"), Base64.strict_encode64(share)] }

    # Every table as JSON. The Lockbox ciphertext column of the waiting
    # shares is the one column that may hold a share, and only encrypted.
    def dump(skip_pending_ciphertext: false)
      connection = ActiveRecord::Base.connection
      connection.tables.map do |table|
        rows = connection.select_all("SELECT * FROM #{connection.quote_table_name(table)}")
        rows = rows.map { |row| row.except("share_ciphertext") } if skip_pending_ciphertext && table == "key_custody_pending_shares"
        rows.to_a.to_json
      end.join
    end

    it "keeps only the Lockbox ciphertext of a waiting share, and nothing after the combine" do # rubocop:disable RSpec/ExampleLength
      record = ask
      shares = [holder_a, holder_b].map { |holder| open_share(key_of(holder), custody.first.key_set) }

      approve(record, holder_a, key_of(holder_a), share: shares[0])
      waiting = KeyCustodyPendingShare.sole
      expect(waiting.share_ciphertext).to be_present
      encodings(shares).each do |value|
        expect(dump).not_to include(value)
        expect(dump(skip_pending_ciphertext: true)).not_to include(waiting.share_ciphertext)
      end

      approve(record, holder_b, key_of(holder_b), share: shares[1])
      expect(record.reload).to be_granted
      expect(KeyCustodyPendingShare.count).to eq(0)

      jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.inspect
      versions = PaperTrail::Version.pluck(:object).to_json
      encodings(shares).each do |value|
        expect(dump).not_to include(value)
        expect(jobs).not_to include(value)
        expect(versions).not_to include(value)
      end
      expect(dump).not_to include(waiting.share_ciphertext)
    end
  end

  describe "the sealed handoff to the requester" do
    it "seals the data key to the requester at the second approval, and the approver sees no image" do
      record = ask
      approve(record, holder_a)

      result = nil
      expect { result = approve(record, holder_b) }.to have_enqueued_mail(BreakGlassMailer, :handoff_ready).with(record)

      expect(result).to have_attributes(error: nil, granted: true)
      expect(result).not_to respond_to(:decrypted)
      record.reload
      expect(record.handoff_sealed_key).to be_present
      expect(record.handoff_expires_at).to be_within(1.minute).of(30.minutes.from_now)
      expect(record.status).to eq(:ready)
      expect(BreakGlassDecryption.count).to eq(0)
      expect(DeliverBreakGlassNoticesJob).not_to have_been_enqueued
      expect(KeyCustodyPendingShare.count).to eq(0)
    end

    it "opens once, for the requester, logs the decryption for them and enqueues the notices" do
      record = granted_record

      handoff = described_class.open!(record, by: requester, ip: "203.0.113.5", user_agent: "Browser")

      expect(open_in_browser(handoff, requester)).to eq(image)
      expect(record.decryptions.sole).to have_attributes(viewer: requester, ip: "203.0.113.5")
      expect(record.reload).to have_attributes(handoff_sealed_key: nil, viewer: requester)
      expect(record.opened_at).to be_present
      expect(verification.events.where(kind: %w[break_glass_granted document_decrypted]).count).to eq(2)
      expect(DeliverBreakGlassNoticesJob).to have_been_enqueued
      expect { described_class.open!(record, by: requester) }.to raise_error(BreakGlass::NotPermitted, /already opened/)
    end

    it "lets nobody but the requester open it, also not an approver" do
      record = granted_record

      [holder_a, holder_b, lead].each do |other|
        expect { described_class.open!(record, by: other) }.to raise_error(BreakGlass::NotPermitted, /Only the person who asked/)
      end
      expect(record.reload.handoff_sealed_key).to be_present
      expect(BreakGlassDecryption.count).to eq(0)
    end

    it "refuses an open after the handoff window, and the sweeper deletes the sealed key" do
      record = granted_record

      travel(VerificationSettings.break_glass_handoff_ttl + 1.minute) do
        expect { described_class.open!(record, by: requester) }.to raise_error(BreakGlass::NotPermitted, /Ask again/)
        expect(record.reload.status).to eq(:expired)
        expect(described_class.sweep_expired_handoffs!).to eq(1)
      end
      expect(record.reload.handoff_sealed_key).to be_nil
      expect(verification.events.where(kind: "break_glass_handoff_expired")).to exist
      expect(BreakGlassDecryption.count).to eq(0)
    end

    it "does not sweep a handoff that is still open" do
      record = granted_record

      expect(described_class.sweep_expired_handoffs!).to eq(0)
      expect(record.reload.handoff_sealed_key).to be_present
    end

    it "opens only with the requester's browser key and only for this request" do
      record = granted_record
      handoff = described_class.open!(record, by: requester)

      expect { open_in_browser(handoff, requester, private_key: KeyCustody::Crypto.generate_key_pair.first) }
        .to raise_error(KeyCustody::Crypto::Error)
      expect { open_in_browser(handoff, requester, private_key: custody.first.private_key) }.to raise_error(KeyCustody::Crypto::Error)
      moved = handoff.with(handoff_aad: "break_glass_handoff|#{ask.public_id}|#{requester.p_id}")
      expect { open_in_browser(moved, requester) }.to raise_error(KeyCustody::Crypto::Error)
    end

    it "writes the notice ladder with the decryption" do
      record = opened_record

      notices = record.decryptions.sole.notices.to_a
      expect(notices.map { |notice| [notice.recipient, notice.recipient_kind] })
        .to contain_exactly([holder_a, "key_holder"], [holder_b, "key_holder"], [lead, "lead"], [member, "member"])
      expect(notices.find(&:member?).due_at).to be_within(1.minute).of(VerificationSettings.member_notice_delay.from_now)
      expect(notices.reject(&:member?).map(&:due_at)).to all(be <= Time.current)
    end

    it "logs one decryption for each request" do
      2.times { opened_record }

      expect(BreakGlassDecryption.count).to eq(2)
      expect(BreakGlassNotice.where(recipient: member).count).to eq(2)
    end

    it "writes nothing and returns nothing when a notice can't be written" do
      record = granted_record
      allow(described_class).to receive(:create_notices!).and_raise(ActiveRecord::RecordNotSaved, "notice failed")

      expect { described_class.open!(record, by: requester) }.to raise_error(ActiveRecord::RecordNotSaved)
      expect(record.reload).to have_attributes(opened_at: nil)
      expect(record.handoff_sealed_key).to be_present
      expect(BreakGlassDecryption.count).to eq(0)
      expect(DeliverBreakGlassNoticesJob).not_to have_been_enqueued
    end
  end

  describe "a database and Lockbox leak" do
    it "holds no plaintext data key in any table, so it can't open the image" do # rubocop:disable RSpec/ExampleLength
      captured = []
      allow(IdDocumentVault).to receive(:open_data_key).and_wrap_original do |original, *args|
        original.call(*args).tap { |key| captured << key.dup }
      end
      record = granted_record
      data_key = captured.sole
      encodings = [data_key, Base64.strict_encode64(data_key), Base64.urlsafe_encode64(data_key, padding: false), data_key.unpack1("H*")]

      dumps = lambda do
        connection = ActiveRecord::Base.connection
        connection.tables.map { |table| connection.select_all("SELECT * FROM #{connection.quote_table_name(table)}").to_a.to_json }.join
      end
      expect(encodings.drop(1)).to all(satisfy { |value| !dumps.call.include?(value) })
      expect(dumps.call.b).not_to include(data_key)
      # The Lockbox-encrypted waiting shares are gone after the grant, so
      # the server key opens nothing.
      expect(KeyCustodyPendingShare.count).to eq(0)
      # The stored blob is sealed to the requester's browser key: the
      # master key does not open it.
      sealed = Base64.strict_decode64(record.handoff_sealed_key)
      expect do
        KeyCustody::Crypto.open_sealed(sealed, private_key: custody.first.private_key, aad: described_class.handoff_aad(record),
                                               info: KeyCustody::Crypto::HANDOFF_SEAL_INFO)
      end.to raise_error(KeyCustody::Crypto::Error)

      described_class.open!(record, by: requester)
      expect(encodings.drop(1)).to all(satisfy { |value| !dumps.call.include?(value) })
    end
  end

  describe "the member notice delay" do
    let(:notice) do
      opened_record
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
