# frozen_string_literal: true

require "rails_helper"

RSpec.describe KeyCustody::Ceremony do
  include ActiveJob::TestHelper

  let!(:keys) { key_holders_with_keys }
  let(:holders) { keys.keys }
  let(:operator) { holders.first }
  let!(:board) { create(:user, is_board: true) }

  describe ".start!" do
    it "lists the holders and their keys, and binds one challenge to the ceremony" do # rubocop:disable RSpec/MultipleExpectations
      options = described_class.start!(by: operator)

      expect(options[:holders].pluck(:id)).to match_array(holders.map(&:public_id))
      expect(options[:holders].map { |holder| holder[:keys].size }).to all(eq(2))
      expect(options[:holders].flat_map { |holder| holder[:keys].pluck(:seal_public_key) }).to all(be_present)
      # One touch: only the operator's own keys may sign.
      expect(options[:request][:allowCredentials].pluck(:id)).to match_array(keys[operator].map(&:external_id))
      expect(options).to include(threshold: 2, share_count: 3)
      expect(KeyCustody::Assertions.decode(options[:request][:challenge])).to start_with("weave:ceremony:#{options[:ceremony]}:")
      expect(KeyCustodyEvent.where(kind: "ceremony_started")).to exist
    end

    it "needs exactly the configured number of key holders" do
      holders.last.update!(identity_key_holder: false)

      expect(described_class.blocker).to include("needs exactly 3")
      expect { described_class.start!(by: operator) }.to raise_error(KeyCustody::Refused)
    end

    it "needs two active hardware keys for each holder" do
      KeyCustody::Enrollment.revoke!(keys[holders.last].first.record, by: holders.last, reason: "Broken")

      expect(described_class.blocker).to include("2 active hardware keys with a seal key")
    end

    it "needs the seal key of each hardware key, set up on the holder's own computer" do
      keys[holders.last].first.record.update_column(:seal_public_key, nil) # rubocop:disable Rails/SkipsModelValidations

      expect(described_class.blocker).to include("with a seal key", holders.last.full_name)
    end

    it "lets only a key holder with a hardware key run it" do
      expect { described_class.start!(by: create(:user, :identity_team)) }.to raise_error(KeyCustody::Refused)
      expect { described_class.start!(by: create(:user, :owner)) }.to raise_error(KeyCustody::Refused, /key holder/)
      expect(described_class.can_discard?(create(:user, :owner))).to be(true)
    end
  end

  describe ".complete!" do
    it "stores the public key, the digests and the wrapped shares, but no share and no private key" do # rubocop:disable RSpec/MultipleExpectations
      result = nil
      expect { result = run_ceremony(operator:, keys:) }.to have_enqueued_mail(KeyCustodyMailer, :event).with(anything, board)

      key_set = result.key_set
      expect(key_set).to be_pending
      expect(key_set.public_key_bytes).to eq(KeyCustody::Crypto.public_key_for(result.private_key))
      expect(key_set.shares.count).to eq(3)
      expect(key_set.wrapped_shares.count).to eq(6)
      expect(KeyCustodyEvent.find_by!(kind: "ceremony_completed").data).to include("share_count" => 3, "threshold" => 2)

      dump = [KeyCustodyKeySet, KeyCustodyShare, KeyCustodyWrappedShare, KeyCustodyEvent].map { |model| model.all.to_json }.join
      [result.private_key, *result.shares.values].each do |secret|
        expect(dump).not_to include(b64url(secret))
        expect(dump).not_to include(secret.unpack1("H*"))
        expect(dump).not_to include(Base64.strict_encode64(secret))
      end
    end

    it "lets each holder open their share with either key" do
      result = run_ceremony(operator:, keys:)

      holders.each do |holder|
        keys[holder].each { |fake| expect(open_share(fake, result.key_set)).to eq(result.shares[holder]) }
      end
    end

    it "needs no other holder's key: each share is sealed to the holder's seal public keys" do
      result = run_ceremony(operator:, keys:)

      sealed = result.key_set.wrapped_shares.includes(:hardware_key, share: :holder)
      expect(sealed.map(&:aad)).to all(start_with("weave key custody sealed share v1|#{result.key_set.public_key}|"))
      expect(sealed.map { |item| item.aad.split("|").last.to_i }).to match_array(result.key_set.shares.flat_map { |share| [share.x] * 2 })
      expect(KeyCustodyChallenge.where(purpose: "ceremony").sole.user).to eq(operator)
    end

    it "binds a sealed share to its key: another key of the holder can't open it" do
      result = run_ceremony(operator:, keys:)
      primary, backup = keys[holders.last]
      backup_copy = result.key_set.share_for(holders.last).wrapped_shares.find_by!(hardware_key: backup.record)

      expect { primary.open(backup_copy) }.to raise_error(KeyCustody::Crypto::Error)
    end

    it "asks PRF on the seal salt of the operator's keys in the one ceremony touch" do
      options = described_class.start!(by: operator)

      expect(options[:operator_id]).to eq(operator.public_id)
      expect(options.dig(:request, :extensions, :prf, :evalByCredential).transform_values { |value| value[:first] })
        .to eq(keys[operator].to_h { |fake| [fake.external_id, fake.record.seal_salt] })
    end

    it "takes the operator's own share as their activation share in the same request" do
      result = run_ceremony(operator:, keys:, operator_share: true)

      expect(KeyCustody::Activation.waiting_holder_ids(result.key_set)).to eq([operator.id])
      expect(KeyCustodyEvent.find_by!(kind: "share_given")).to have_attributes(actor: operator, key_set: result.key_set)
      expect(KeyCustodyEvent.find_by!(kind: "share_given").data).to include("via" => "ceremony")

      # The other two still activate on their own computers.
      expect(submit_activation(holders[1], keys[holders[1]].first, result.key_set)).to eq(:waiting)
      expect(submit_activation(holders[2], keys[holders[2]].first, result.key_set)).to eq(:activated)
    end

    it "refuses an operator share that does not match the operator's digest, and makes no key set" do
      options = described_class.start!(by: operator)
      private_key, public_key = KeyCustody::Crypto.generate_key_pair
      public_b64 = Base64.strict_encode64(public_key)
      split = KeyCustody::Shamir.split(private_key, share_count: 3, threshold: 2)
      entries = keys.each_with_index.map do |(holder, fakes), index|
        { holder_id: holder.public_id, x: split[index].getbyte(-1), digest: KeyCustody::Crypto.share_digest(split[index], public_key:),
          wrapped: fakes.map { |fake| { credential_id: fake.external_id, sealed: seal_for(fake, split[index], key_set_public_key_b64: public_b64, holder:) } }
}
      end

      expect do
        described_class.complete!(by: operator, ceremony: options[:ceremony], public_key: public_b64, shares: entries,
                                  credential: keys[operator].first.assert(options[:request][:challenge]),
                                  operator_share: b64url(split[1]))
      end.to raise_error(KeyCustody::Refused, /operator's share/)
      expect(KeyCustodyKeySet.count).to eq(0)
    end

    it "refuses a ceremony that misses a holder" do
      options = described_class.start!(by: operator)

      expect do
        described_class.complete!(by: operator, ceremony: options[:ceremony], public_key: Base64.strict_encode64(SecureRandom.random_bytes(32)),
                                  shares: [], credential: keys[operator].first.assert(options[:request][:challenge]))
      end.to raise_error(KeyCustody::Refused)
      expect(KeyCustodyKeySet.count).to eq(0)
    end

    it "refuses a sealed share that is not the right size" do
      options = described_class.start!(by: operator)
      entries = holders.each_with_index.map do |holder, index|
        { holder_id: holder.public_id, x: index + 1, digest: "a" * 64,
          wrapped: keys[holder].map { |fake| { credential_id: fake.external_id, sealed: b64url("short") } }
}
      end

      expect do
        described_class.complete!(by: operator, ceremony: options[:ceremony], public_key: Base64.strict_encode64(SecureRandom.random_bytes(32)),
                                  shares: entries, credential: keys[operator].first.assert(options[:request][:challenge]))
      end.to raise_error(KeyCustody::Refused, /not valid/)
    end

    it "refuses an assertion from a key that is not the operator's" do
      expect { run_ceremony(operator:, keys:, operator_key: keys[holders[1]].first) }.to raise_error(KeyCustody::Refused, /not one that can open/)
      expect(KeyCustodyKeySet.count).to eq(0)
    end

    it "refuses the same ceremony twice" do
      options = described_class.start!(by: operator)
      KeyCustodyChallenge.find_by!(subject: options[:ceremony]).consume!

      expect do
        described_class.complete!(by: operator, ceremony: options[:ceremony], public_key: "x", shares: [], credential: {})
      end.to raise_error(KeyCustody::Refused, /already used/)
    end
  end

  describe "activation" do
    it "activates only after all three holders give their own share" do # rubocop:disable RSpec/MultipleExpectations
      result = run_ceremony(operator:, keys:)

      expect(submit_activation(holders[0], keys[holders[0]].first, result.key_set)).to eq(:waiting)
      expect(submit_activation(holders[2], keys[holders[2]].last, result.key_set)).to eq(:waiting)
      expect(result.key_set.reload).to be_pending
      expect(KeyCustody::Activation.progress(result.key_set)).to eq(new: 2, old: 0)
      expect(submit_activation(holders[1], keys[holders[1]].first, result.key_set)).to eq(:activated)

      expect(result.key_set.reload).to be_active
      expect(KeyCustody.current_key_set).to eq(result.key_set)
      expect(KeyCustody::PendingShares.size).to eq(0)
    end

    it "logs one share_given row for each holder's share, so the log shows who is missing" do
      result = run_ceremony(operator:, keys:)
      submit_activation(holders[0], keys[holders[0]].first, result.key_set)
      submit_activation(holders[2], keys[holders[2]].first, result.key_set)

      given = KeyCustodyEvent.where(kind: "share_given")
      expect(given.map(&:actor)).to contain_exactly(holders[0], holders[2])
      expect(given.map(&:key_set).uniq).to eq([result.key_set])
      expect(given.first.data).to include("share" => "new", "via" => "activation")
      expect(given.first.summary).to include(holders[0].full_name, "new share", result.key_set.public_id)
      expect(given.map(&:actor)).not_to include(holders[1])
      expect(given.to_a.to_json).not_to include(Base64.urlsafe_encode64(result.shares[holders[0]], padding: false))
    end

    it "refuses a share that is not the holder's" do
      result = run_ceremony(operator:, keys:)
      options = KeyCustody::Activation.options(holders[0], result.key_set)

      expect do
        KeyCustody::Activation.submit!(holders[0], result.key_set, credential: keys[holders[0]].first.assert(options[:request][:challenge]),
                                                                   new_share: b64url(result.shares[holders[1]]))
      end.to raise_error(KeyCustody::Refused, /not your share/)
    end

    it "refuses shares that do not rebuild the public key, logs it and tells the board" do # rubocop:disable RSpec/ExampleLength
      result = run_ceremony(operator:, keys:)
      # A broken ceremony page: the digests match the shares, but the shares
      # belong to another key than the public key.
      other = KeyCustody::Shamir.split(KeyCustody::Crypto.generate_key_pair.first, share_count: 3, threshold: 2)
      result.key_set.shares.each_with_index do |share, index|
        KeyCustodyShare.where(id: share.id).update_all(x: other[index].getbyte(-1), # rubocop:disable Rails/SkipsModelValidations
                                                       digest: KeyCustody::Crypto.share_digest(other[index], public_key: result.key_set.public_key_bytes))
      end
      key_set = result.key_set.reload
      submit = lambda do |holder, share|
        options = KeyCustody::Activation.options(holder, key_set)
        KeyCustody::Activation.submit!(holder, key_set, credential: keys[holder].first.assert(options[:request][:challenge]), new_share: b64url(share))
      end
      share_of = ->(holder) { other.find { |share| share.getbyte(-1) == key_set.shares.find_by!(holder:).x } }
      submit.call(holders[0], share_of.call(holders[0]))
      submit.call(holders[1], share_of.call(holders[1]))

      expect { submit.call(holders[2], share_of.call(holders[2])) }
        .to raise_error(KeyCustody::Refused, /do not rebuild/)
      expect(key_set.reload).to be_pending
      expect(KeyCustodyEvent.where(kind: "unlock_failed")).to exist
    end

    it "lets an owner or a holder discard a pending set" do
      result = run_ceremony(operator:, keys:)

      described_class.discard!(result.key_set, by: operator, reason: "A key holder left the room")

      expect(result.key_set.reload).to be_retired
      expect(result.key_set.wrapped_shares).to be_empty
    end
  end
end
