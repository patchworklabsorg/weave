# frozen_string_literal: true

require "rails_helper"

RSpec.describe KeyCustody::Enrollment do
  include ActiveJob::TestHelper

  let(:holder) { create(:user, :key_holder) }

  describe ".enroll!" do
    it "registers a hardware key with PRF support and logs it" do
      fake = enroll_fake_key(holder, role: "primary")

      expect(fake.record).to have_attributes(user: holder, role: "primary", revoked_at: nil)
      expect(fake.record.public_key).to be_present
      expect(KeyCustodyEvent.where(kind: "hardware_key_enrolled", subject: holder)).to exist
    end

    it "lets a holder enroll a primary and a backup key, and no more" do
      enroll_fake_key(holder, role: "primary")
      enroll_fake_key(holder, role: "backup")

      expect(described_class.can_enroll?(holder)).to be(false)
      expect { described_class.creation_options(holder) }.to raise_error(KeyCustody::Refused, /fewer than 2/)
    end

    it "tells the board about each new key" do
      board = create(:user, is_board: true)

      expect { enroll_fake_key(holder, role: "primary") }.to have_enqueued_mail(KeyCustodyMailer, :event).with(anything, board)
    end

    it "refuses the same role twice" do
      enroll_fake_key(holder, role: "primary")

      expect { enroll_fake_key(holder, role: "primary") }.to raise_error(KeyCustody::Refused, /role/)
    end

    it "refuses a key without the PRF extension" do
      expect { enroll_fake_key(holder, role: "primary", prf: false) }.to raise_error(KeyCustody::Refused, /PRF/)
      expect(holder.identity_hardware_keys).to be_empty
    end

    it "refuses a person who is not a key holder" do
      expect { described_class.creation_options(create(:user, :identity_team)) }.to raise_error(KeyCustody::Refused)
    end

    it "asks for a cross-platform key with PRF and user verification" do
      options = described_class.creation_options(holder)

      expect(options[:extensions]).to eq(prf: { eval: { first: options[:seal_salt] } })
      expect(options[:seal_salt]).to eq(described_class.seal_salt_for(options[:challenge]))
      expect(options[:authenticatorSelection]).to include(authenticatorAttachment: "cross-platform", userVerification: "required")
      expect(KeyCustody::Assertions.decode(options[:challenge])).to start_with("weave:enroll:#{holder.public_id}:")
    end

    it "refuses a replayed registration" do
      fake = KeyCustodyHelpers::FakeKey.new
      options = described_class.creation_options(holder)
      credential = fake.client.create(challenge: options[:challenge], user_verified: true)
      credential["clientExtensionResults"] = { "prf" => { "enabled" => true } }
      described_class.enroll!(holder, credential:, role: "primary")

      expect { described_class.enroll!(holder, credential:, role: "backup") }.to raise_error(KeyCustody::Refused, /challenge/)
    end

    it "refuses a registration made for another person's challenge" do
      other = create(:user, :key_holder)
      fake = KeyCustodyHelpers::FakeKey.new
      options = described_class.creation_options(other)
      credential = fake.client.create(challenge: options[:challenge], user_verified: true)
      credential["clientExtensionResults"] = { "prf" => { "enabled" => true } }

      expect { described_class.enroll!(holder, credential:, role: "primary") }.to raise_error(KeyCustody::Refused, /challenge/)
    end
  end

  describe "one-touch enrollment (PRF at creation)" do
    def created_credential(fake, options)
      credential = fake.client.create(challenge: options[:challenge], user_verified: true)
      credential["clientExtensionResults"] = { "prf" => { "enabled" => true } }
      credential
    end

    it "stores the seal salt of the options and the seal key from the registration" do
      fake = KeyCustodyHelpers::FakeKey.new
      options = described_class.creation_options(holder)
      seal_public_key = Base64.strict_encode64(fake.seal_public_key_for(options[:seal_salt]))

      key = described_class.enroll!(holder, credential: created_credential(fake, options), role: "primary", seal_public_key:)
      fake.record = key

      expect(key).to be_sealable
      expect(key.seal_salt).to eq(options[:seal_salt])
      expect(key.seal_public_key_bytes).to eq(fake.seal_public_key)
      expect(KeyCustodyEvent.where(kind: "seal_key_registered", subject: holder).sole.data).to include("at_enrollment" => true)
      expect { described_class.seal_key_options(holder, key) }.to raise_error(KeyCustody::Refused, /already/)
    end

    it "uses the same seal salt for the second touch when the key gave no PRF output" do
      fake = KeyCustodyHelpers::FakeKey.new
      options = described_class.creation_options(holder)

      key = described_class.enroll!(holder, credential: created_credential(fake, options), role: "primary")

      expect(key).not_to be_sealable
      expect(key.seal_salt).to eq(options[:seal_salt])
      expect(described_class.seal_key_options(holder, key).dig(:extensions, :prf, :evalByCredential, key.external_id, :first))
        .to eq(options[:seal_salt])
    end

    it "refuses a seal key sent with a registration for an unknown challenge, and stores nothing" do
      fake = KeyCustodyHelpers::FakeKey.new
      described_class.creation_options(holder)
      forged = KeyCustody::Assertions.encode("weave:enroll:#{holder.public_id}:".b + SecureRandom.random_bytes(32))
      credential = created_credential(fake, { challenge: forged })
      seal_public_key = Base64.strict_encode64(fake.seal_public_key_for(described_class.seal_salt_for(forged)))

      expect { described_class.enroll!(holder, credential:, role: "primary", seal_public_key:) }
        .to raise_error(KeyCustody::Refused, /challenge/)
      expect(holder.identity_hardware_keys).to be_empty
    end

    it "refuses a seal key sent with another person's registration" do
      other = create(:user, :key_holder)
      fake = KeyCustodyHelpers::FakeKey.new
      options = described_class.creation_options(other)
      seal_public_key = Base64.strict_encode64(fake.seal_public_key_for(options[:seal_salt]))

      expect { described_class.enroll!(holder, credential: created_credential(fake, options), role: "primary", seal_public_key:) }
        .to raise_error(KeyCustody::Refused, /challenge/)
      expect(IdentityHardwareKey.count).to eq(0)
    end

    it "refuses a seal key of the wrong length" do
      fake = KeyCustodyHelpers::FakeKey.new
      options = described_class.creation_options(holder)

      expect do
        described_class.enroll!(holder, credential: created_credential(fake, options), role: "primary",
                                        seal_public_key: Base64.strict_encode64("short"))
      end.to raise_error(KeyCustody::Refused, /32 bytes/)
      expect(holder.identity_hardware_keys).to be_empty
    end

    it "refuses a key whose PRF is not enabled, even with a seal key" do
      fake = KeyCustodyHelpers::FakeKey.new
      options = described_class.creation_options(holder)
      credential = created_credential(fake, options)
      credential["clientExtensionResults"] = { "prf" => { "enabled" => false } }
      seal_public_key = Base64.strict_encode64(fake.seal_public_key_for(options[:seal_salt]))

      expect { described_class.enroll!(holder, credential:, role: "primary", seal_public_key:) }
        .to raise_error(KeyCustody::Refused, /PRF/)
      expect(holder.identity_hardware_keys).to be_empty
    end
  end

  describe ".register_seal_key!" do
    it "gives each key its own seal salt, and stores only the seal public key" do
      primary = enroll_fake_key(holder, role: "primary", seal: false)
      backup = enroll_fake_key(holder, role: "backup", seal: false)
      expect(primary.record.seal_salt).not_to eq(backup.record.seal_salt)
      expect(primary.record.seal_public_key).to be_nil

      register_seal_key(holder, primary)

      expect(primary.record.seal_public_key_bytes).to eq(primary.seal_public_key)
      expect(primary.record.attributes.values.join).not_to include(Base64.strict_encode64(primary.seal_private_key))
    end

    it "asks for PRF on the key's seal salt, for that key only" do
      fake = enroll_fake_key(holder, role: "primary", seal: false)

      options = described_class.seal_key_options(holder, fake.record)

      expect(options[:allowCredentials].pluck(:id)).to eq([fake.external_id])
      expect(options.dig(:extensions, :prf, :evalByCredential, fake.external_id, :first)).to eq(fake.record.seal_salt)
    end

    it "refuses a second seal key, a bad key length and another person's key" do
      fake = enroll_fake_key(holder, role: "primary")

      expect { described_class.seal_key_options(holder, fake.record) }.to raise_error(KeyCustody::Refused, /already/)
      other = enroll_fake_key(holder, role: "backup", seal: false)
      expect { register_seal_key(holder, other, public_key: "short") }.to raise_error(KeyCustody::Refused, /32 bytes/)
      expect { described_class.seal_key_options(create(:user, :key_holder), other.record) }.to raise_error(KeyCustody::Refused, /holder/)
    end
  end

  describe ".revoke!" do
    let!(:custody) { setup_key_custody }
    let(:keys) { custody.last }
    let(:holder) { keys.keys.first }
    let!(:board) { create(:user, is_board: true) }

    it "revokes a lost key, deletes its wrapped share and tells the board" do
      key = keys[holder].first.record

      expect { described_class.revoke!(key, by: holder, reason: "Lost on the train") }
        .to have_enqueued_mail(KeyCustodyMailer, :event).with(anything, board)

      expect(key.reload).not_to be_active
      expect(key.wrapped_shares).to be_empty
      expect(KeyCustodyEvent.where(kind: "hardware_key_revoked", subject: holder)).to exist
      expect(KeyCustody.current_key_set).to be_active
    end

    it "marks the key set compromised when a holder has no key left" do
      keys[holder].each { |fake| described_class.revoke!(fake.record, by: holder, reason: "Both keys stolen") }

      key_set = custody.first.key_set.reload
      expect(key_set).to be_compromised
      expect(key_set.compromised_reason).to eq("holder_lost_all_keys")
      expect(KeyCustody.warning).to include("compromised")
    end

    it "stops a pending set from activating when a holder has no key left that opens their share of it" do
      operator = keys.keys.first
      pending = run_ceremony(operator:, keys:).key_set
      other = keys.keys.second

      keys[other].each { |fake| described_class.revoke!(fake.record, by: other, reason: "Both keys stolen") }

      expect(pending.reload.compromised_at).to be_present
      expect(KeyCustody::Activation.can_submit?(operator, pending)).to be(false)
      expect { submit_activation(operator, keys[operator].first, pending) }.to raise_error(KeyCustody::Refused)
    end

    it "lets an owner revoke, and nobody else" do
      key = keys[holder].first.record

      expect { described_class.revoke!(key, by: keys.keys.second, reason: "Lost") }.to raise_error(KeyCustody::Refused)
      expect { described_class.revoke!(key, by: holder, reason: "") }.to raise_error(KeyCustody::Refused)
      described_class.revoke!(key, by: create(:user, :owner), reason: "Holder reported it lost")
      expect(key.reload).not_to be_active
    end
  end
end
