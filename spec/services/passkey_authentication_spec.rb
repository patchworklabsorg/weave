# frozen_string_literal: true

require "rails_helper"

RSpec.describe PasskeyAuthentication do
  let(:user) { create(:user, :verified) }
  let(:client) { fake_passkey_client }

  describe ".registration_options" do
    it "asks for a discoverable passkey with user verification" do
      options = described_class.registration_options(user)

      expect(options.authenticator_selection).to include(resident_key: "required", user_verification: "required")
      expect(options.user.id).to eq(user.reload.webauthn_id)
    end

    it "keeps the same user handle for every passkey" do
      first = described_class.registration_options(user).user.id
      second = described_class.registration_options(user.reload).user.id

      expect(second).to eq(first)
    end

    it "excludes the passkeys the user already has" do
      passkey = register_passkey(user, client: client)

      options = described_class.registration_options(user)

      expect(options.exclude_credentials.pluck(:id)).to eq([passkey.external_id])
    end
  end

  describe ".register!" do
    it "stores the passkey with its nickname" do
      passkey = register_passkey(user, client: client, nickname: "  Work laptop  ")

      expect(passkey).to be_persisted
      expect(passkey.user).to eq(user)
      expect(passkey.nickname).to eq("Work laptop")
    end

    it "refuses a passkey made without user verification" do
      options = described_class.registration_options(user)
      credential = client.create(challenge: options.challenge, user_verified: false)

      expect do
        described_class.register!(user, credential: credential.to_json, challenge: options.challenge)
      end.to raise_error(described_class::Failure) { |e| expect(e.reason).to eq(:invalid) }
    end

    it "refuses a credential signed for another challenge" do
      options = described_class.registration_options(user)
      credential = client.create(challenge: WebAuthn.configuration.encoder.encode(SecureRandom.random_bytes(32)), user_verified: true)

      expect do
        described_class.register!(user, credential: credential.to_json, challenge: options.challenge)
      end.to raise_error(described_class::Failure) { |e| expect(e.reason).to eq(:invalid) }
    end

    it "refuses when the challenge is missing" do
      expect do
        described_class.register!(user, credential: "{}", challenge: nil)
      end.to raise_error(described_class::Failure) { |e| expect(e.reason).to eq(:expired) }
    end

    it "refuses input that is not a credential" do
      expect do
        described_class.register!(user, credential: "not json", challenge: "abc")
      end.to raise_error(described_class::Failure) { |e| expect(e.reason).to eq(:invalid) }
    end
  end

  describe ".authenticate!" do
    let!(:passkey) { register_passkey(user, client: client) }
    let(:challenge) { described_class.sign_in_options.challenge }

    it "returns the passkey and records its use" do
      result = described_class.authenticate!(credential: passkey_assertion(client, challenge, user: user), challenge: challenge)

      expect(result).to eq(passkey)
      expect(passkey.reload.last_used_at).to be_present
      expect(passkey.sign_count).to be > 0
    end

    it "refuses an assertion without user verification" do
      credential = client.get(challenge: challenge, user_verified: false).to_json

      expect do
        described_class.authenticate!(credential: credential, challenge: challenge)
      end.to raise_error(described_class::Failure) { |e| expect(e.reason).to eq(:invalid) }
    end

    it "refuses an assertion for another challenge" do
      credential = passkey_assertion(client, challenge, user: user)

      expect do
        described_class.authenticate!(credential: credential, challenge: described_class.sign_in_options.challenge)
      end.to raise_error(described_class::Failure) { |e| expect(e.reason).to eq(:invalid) }
    end

    it "refuses a passkey that Weave does not know" do
      passkey.destroy!

      expect do
        described_class.authenticate!(credential: passkey_assertion(client, challenge, user: user), challenge: challenge)
      end.to raise_error(described_class::Failure) { |e| expect(e.reason).to eq(:unknown) }
    end

    it "refuses a user handle that belongs to another account" do
      other = create(:user, :verified)
      other.ensure_webauthn_id!

      expect do
        described_class.authenticate!(credential: passkey_assertion(client, challenge, user: other), challenge: challenge)
      end.to raise_error(described_class::Failure) { |e| expect(e.reason).to eq(:unknown) }
    end

    it "refuses a user who cannot sign in" do
      user.update_column(:locked_at, Time.current) # rubocop:disable Rails/SkipsModelValidations

      expect do
        described_class.authenticate!(credential: passkey_assertion(client, challenge, user: user), challenge: challenge)
      end.to raise_error(described_class::Failure) { |e| expect(e.reason).to eq(:inactive) }
    end

    it "turns the passkey off when its sign count goes back" do
      passkey.update!(sign_count: 100)
      credential = passkey_assertion(client, challenge, user: user, sign_count: 5)

      expect do
        described_class.authenticate!(credential: credential, challenge: challenge)
      end.to raise_error(described_class::Failure) { |e| expect(e.reason).to eq(:compromised) }
      expect(passkey.reload).to be_compromised
    end

    it "refuses a passkey that is turned off" do
      passkey.update!(compromised_at: Time.current)

      expect do
        described_class.authenticate!(credential: passkey_assertion(client, challenge, user: user), challenge: challenge)
      end.to raise_error(described_class::Failure) { |e| expect(e.reason).to eq(:compromised) }
    end
  end
end
