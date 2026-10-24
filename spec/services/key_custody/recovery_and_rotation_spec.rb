# frozen_string_literal: true

require "rails_helper"

RSpec.describe KeyCustody::Recovery do
  include ActiveJob::TestHelper

  let!(:custody) { setup_key_custody }
  let!(:board) { create(:user, is_board: true) }
  let(:requester) { create(:user, :identity_team) }

  def old_result = custody.first

  def keys = custody.last

  def holders = keys.keys

  def holder = holders.first

  def image = Rails.root.join("spec/fixtures/files/id_document.png").binread

  def rewrap(user, remaining:, new_fake:, signer: remaining)
    options = described_class.options(user, new_key: new_fake.record)
    share = remaining.open(options[:old][:wrapped].fetch(remaining.external_id))
    sealed = b64url(KeyCustody::Crypto.seal_share(share, public_key: Base64.strict_decode64(options[:new][:seal_public_key]),
                                                         aad: options[:new][:aad]))
    described_class.rewrap!(user, new_key: new_fake.record, old_credential: signer.assert(options[:old][:challenge]), sealed:)
  end

  def break_glass_with(verification, pairs)
    record = BreakGlass.request(verification, by: requester, reason: "Fraud report: compare the document.",
                                                    requester_public_key: browser_public_key(requester)).record
    pairs.map { |user, fake| approve_with_key(record, user, fake) }.tap { record.reload }
    record.reload
  end

  describe "a holder lost one key" do
    def lost = keys[holder].first

    def remaining = keys[holder].last

    before { KeyCustody::Enrollment.revoke!(lost.record, by: holder, reason: "Lost on the train") }

    it "opens the share with the other key and wraps it for a new key, and the board is told" do
      new_fake = enroll_fake_key(holder, role: "primary")

      expect { rewrap(holder, remaining:, new_fake:) }.to have_enqueued_mail(KeyCustodyMailer, :event).with(anything, board)

      expect(open_share(new_fake, old_result.key_set)).to eq(old_result.shares[holder])
      expect(KeyCustodyEvent.where(kind: "share_rewrapped", subject: holder)).to exist
      expect(old_result.key_set.reload).to be_active
    end

    it "lets the new key approve break-glass" do
      new_fake = enroll_fake_key(holder, role: "primary")
      rewrap(holder, remaining:, new_fake:)
      verification = seal!(create(:verification, :verified))

      record = break_glass_with(verification, [[holder, new_fake], [holders.second, keys[holders.second].first]])

      expect(record).to be_granted
    end

    it "refuses a rewrap signed only by the new key" do
      new_fake = enroll_fake_key(holder, role: "primary")

      expect { rewrap(holder, remaining:, new_fake:, signer: new_fake) }.to raise_error(KeyCustody::Refused, /not one that can open/)
    end

    it "refuses the lost key, which can't open anything any more" do
      expect(described_class.keys_for(old_result.key_set.share_for(holder))).to contain_exactly(remaining.record)
      expect(lost.record.wrapped_shares).to be_empty
    end
  end

  describe "a holder lost both keys: rotation" do
    let!(:sealed_before) { seal!(create(:verification, :verified)) }

    before do
      keys[holder].each { |fake| KeyCustody::Enrollment.revoke!(fake.record, by: holder, reason: "Bag stolen") }
    end

    it "marks the set compromised, and recovery can't help" do
      expect(old_result.key_set.reload).to be_compromised
      new_fake = enroll_fake_key(holder, role: "primary")

      expect { described_class.options(holder, new_key: new_fake.record) }.to raise_error(KeyCustody::Refused, /rotation/)
    end

    it "rotates: a new key set, the stored data keys re-wrapped, the old shares useless" do # rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations
      new_keys = keys.merge(holder => [enroll_fake_key(holder, role: "primary"), enroll_fake_key(holder, role: "backup")])
      new_result = run_ceremony(operator: holders.second, keys: new_keys)
      key_set = new_result.key_set
      expect(key_set.rotated_from).to eq(old_result.key_set)

      # The holder who lost both keys gives only the new share. The other two
      # give the old share and the new share with one touch.
      expect(submit_activation(holder, new_keys[holder].first, key_set)).to eq(:waiting)
      expect(submit_activation(holders.second, new_keys[holders.second].first, key_set)).to eq(:waiting)
      outcome = nil
      expect { outcome = submit_activation(holders.third, new_keys[holders.third].last, key_set) }
        .to have_enqueued_mail(KeyCustodyMailer, :event).with(anything, board).at_least(:once)
      expect(outcome).to eq(:activated)

      expect(key_set.reload).to be_active
      expect(old_result.key_set.reload).to be_retired
      expect(old_result.key_set.wrapped_shares).to be_empty
      expect(sealed_before.reload.sealed_document.key_set).to eq(key_set)
      expect(KeyCustodyEvent.find_by!(kind: "rotation_completed").data).to include("rewrapped" => 1)

      # The image opens with the new shares.
      private_key = new_result.private_key
      data_key = IdDocumentVault.open_data_key(sealed_before, private_key)
      expect(KeyCustody::Crypto.decrypt(sealed_before.sealed_document.ciphertext.download, key: data_key,
                                                                                           aad: "verification:#{sealed_before.id}")).to eq(image)

      # The old shares no longer open it.
      expect do
        KeyCustody::Unlock.with_master_key(key_set, [old_result.shares[holders.second].dup, old_result.shares[holders.third].dup]) { nil }
      end.to raise_error(KeyCustody::Refused)

      # Break-glass works with the new keys, and refuses an old share.
      record = BreakGlass.request(sealed_before, by: requester, reason: "Fraud report: compare the document.",
                                                     requester_public_key: browser_public_key(requester)).record
      stale = approve_with_key(record, holders.second, new_keys[holders.second].first, share: old_result.shares[holders.second])
      expect(stale.error).to include("not your share")
      approve_with_key(record, holder, new_keys[holder].first)
      approve_with_key(record, holders.third, new_keys[holders.third].first)
      expect(record.reload).to be_granted
      expect(open_in_browser(BreakGlass.open!(record, by: requester), requester)).to eq(image)
    end

    it "waits for the old shares before it activates a rotation" do
      new_keys = keys.merge(holder => [enroll_fake_key(holder, role: "primary"), enroll_fake_key(holder, role: "backup")])
      key_set = run_ceremony(operator: holders.second, keys: new_keys).key_set

      submit_activation(holder, new_keys[holder].first, key_set)
      expect(KeyCustody::Activation.progress(key_set)).to eq(new: 1, old: 0)
      submit_activation(holders.second, new_keys[holders.second].first, key_set)

      expect(KeyCustody::Activation.progress(key_set)).to eq(new: 2, old: 1)
      expect(key_set.reload).to be_pending
    end
  end

  describe "the key holder set changed" do
    let(:owner) { create(:user, :owner, :verified) }

    it "marks the current set compromised through the governance hook, and the board is told" do
      expect { IdentityGovernance.remove_member(holder, by: owner, reason: "Left the org.") }
        .to have_enqueued_mail(KeyCustodyMailer, :event).with(anything, board)

      key_set = old_result.key_set.reload
      expect(key_set).to be_compromised
      expect(key_set.compromised_reason).to eq("key_holder_removed")
      expect(KeyCustody.warning).to include("compromised")
    end

    it "rotates to the new holder set: the removed holder can't take part" do
      IdentityGovernance.remove_member(holder, by: owner, reason: "Left the org.")
      newcomer = create(:user, :key_holder)
      new_keys = keys.except(holder).merge(newcomer => [enroll_fake_key(newcomer, role: "primary"), enroll_fake_key(newcomer, role: "backup")])
      key_set = run_ceremony(operator: holders.second, keys: new_keys).key_set

      expect(KeyCustody::Activation.can_submit?(holder.reload, key_set)).to be(false)
      submit_activation(holders.second, new_keys[holders.second].first, key_set)
      expect(submit_activation(holders.third, new_keys[holders.third].first, key_set)).to eq(:waiting)
      expect(submit_activation(newcomer, new_keys[newcomer].first, key_set)).to eq(:activated)

      expect(key_set.reload).to be_active
      expect(key_set.shares.map(&:holder)).to contain_exactly(holders.second, holders.third, newcomer)
    end

    it "refuses to activate a pending set made before the holders changed" do
      pending_set = KeyCustodyKeySet.create!(public_key: Base64.strict_encode64(KeyCustody::Crypto.generate_key_pair.last),
                                             threshold: 2, share_count: 3, status: "pending", rotated_from: old_result.key_set)

      IdentityGovernance.remove_member(holder, by: owner, reason: "Left the org.")

      expect(pending_set.reload.compromised_at).to be_present
      expect(KeyCustody::Activation.can_submit?(holders.second, pending_set)).to be(false)
    end
  end
end
