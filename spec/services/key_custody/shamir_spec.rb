# frozen_string_literal: true

require "rails_helper"

RSpec.describe KeyCustody::Shamir do
  # Shares made by the audited JavaScript library "shamir-secret-sharing"
  # (the one the ceremony page uses). Made with
  # spec/fixtures/files/key_custody/make_vectors.mjs.
  let(:vectors) { JSON.parse(Rails.root.join("spec/fixtures/files/key_custody/shamir_vectors.json").read) }

  def hex(value) = [value].pack("H*")

  describe "known-answer vectors from the JavaScript library" do
    it "rebuilds each secret from every subset of threshold shares" do
      vectors.each do |vector|
        shares = vector["shares"].map { |share| hex(share) }
        shares.combination(vector["threshold"]).each do |subset|
          expect(described_class.combine(subset).unpack1("H*")).to eq(vector["secret"])
        end
      end
    end

    it "rebuilds each secret from all shares too" do
      vectors.each do |vector|
        expect(described_class.combine(vector["shares"].map { |share| hex(share) }).unpack1("H*")).to eq(vector["secret"])
      end
    end

    it "uses the same field as the library (the generator 0xe5 squared is 0x4c)" do
      expect(described_class.multiply(0xe5, 0xe5)).to eq(0x4c)
    end
  end

  describe "field arithmetic" do
    it "has an inverse for each value that is not 0" do
      (1..255).each { |value| expect(described_class.multiply(value, described_class.inverse(value))).to eq(1) }
    end

    it "multiplies by 0 and 1 as expected" do
      (0..255).each do |value|
        expect(described_class.multiply(value, 0)).to eq(0)
        expect(described_class.multiply(value, 1)).to eq(value)
      end
    end
  end

  describe ".split and .combine" do
    let(:secret) { SecureRandom.random_bytes(32) }

    it "rebuilds the secret from every 2-of-3 subset" do
      shares = described_class.split(secret, share_count: 3, threshold: 2)

      expect(shares.map(&:bytesize)).to all(eq(33))
      shares.combination(2).each { |pair| expect(described_class.combine(pair)).to eq(secret) }
      shares.permutation(2).each { |pair| expect(described_class.combine(pair)).to eq(secret) }
    end

    it "gives distinct x values that are not 0" do
      xs = described_class.split(secret, share_count: 3, threshold: 2).map { |share| share.getbyte(-1) }

      expect(xs.uniq.size).to eq(3)
      expect(xs).not_to include(0)
    end

    it "rebuilds the secret from every 3-of-5 subset" do
      shares = described_class.split(secret, share_count: 5, threshold: 3)

      shares.combination(3).each { |subset| expect(described_class.combine(subset)).to eq(secret) }
    end

    it "gives a different value with fewer shares than the threshold" do
      shares = described_class.split(secret, share_count: 5, threshold: 3)

      expect(described_class.combine(shares.first(2))).not_to eq(secret)
    end

    it "refuses one share" do
      share = described_class.split(secret, share_count: 3, threshold: 2).first

      expect { described_class.combine([share]) }.to raise_error(described_class::Error, /At least 2/)
    end

    it "refuses two shares with the same x value" do
      share = described_class.split(secret, share_count: 3, threshold: 2).first

      expect { described_class.combine([share, share.dup]) }.to raise_error(described_class::Error, /same x/)
    end

    it "refuses shares of different lengths" do
      shares = described_class.split(secret, share_count: 3, threshold: 2)

      expect { described_class.combine([shares[0], shares[1].byteslice(1..)]) }.to raise_error(described_class::Error, /same length/)
    end

    it "gives a wrong secret, not an error, for a share from another split" do
      shares = described_class.split(secret, share_count: 3, threshold: 2)
      other = described_class.split(SecureRandom.random_bytes(32), share_count: 3, threshold: 2)
      foreign = other.find { |share| share.getbyte(-1) != shares[0].getbyte(-1) }

      expect(described_class.combine([shares[0], foreign])).not_to eq(secret)
    end

    it "refuses bad parameters" do
      expect { described_class.split("", share_count: 3, threshold: 2) }.to raise_error(described_class::Error)
      expect { described_class.split(secret, share_count: 1, threshold: 2) }.to raise_error(described_class::Error)
      expect { described_class.split(secret, share_count: 2, threshold: 3) }.to raise_error(described_class::Error)
    end
  end

  describe "the authenticated check after combining" do
    it "refuses a wrong share through the master public key" do
      private_key, public_key = KeyCustody::Crypto.generate_key_pair
      key_set = KeyCustodyKeySet.new(public_key: Base64.strict_encode64(public_key), threshold: 2, share_count: 3)
      shares = described_class.split(private_key, share_count: 3, threshold: 2)
      wrong = shares[1].dup
      # Change a middle byte. X25519 clamps the low bits of byte 0 and the high
      # bits of byte 31, so a change that lands only there gives the same key.
      wrong.setbyte(10, wrong.getbyte(10) ^ 1)

      expect { KeyCustody::Unlock.with_master_key(key_set, [shares[0].dup, wrong]) { nil } }
        .to raise_error(KeyCustody::Refused, /do not rebuild the master key/)
      expect(KeyCustody::Unlock.with_master_key(key_set, [shares[0].dup, shares[2].dup]) { |key| key.dup }).to eq(private_key)
    end

    it "wipes the shares and the key after the block" do
      private_key, public_key = KeyCustody::Crypto.generate_key_pair
      key_set = KeyCustodyKeySet.new(public_key: Base64.strict_encode64(public_key), threshold: 2, share_count: 3)
      shares = described_class.split(private_key, share_count: 3, threshold: 2).first(2)
      seen = nil

      KeyCustody::Unlock.with_master_key(key_set, shares) { |key| seen = key }

      expect(seen).to be_empty
      expect(shares).to all(be_empty)
    end
  end
end
