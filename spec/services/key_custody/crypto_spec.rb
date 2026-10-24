# frozen_string_literal: true

require "rails_helper"

RSpec.describe KeyCustody::Crypto do
  let(:pair) { described_class.generate_key_pair }
  let(:private_key) { pair.first }
  let(:public_key) { pair.last }

  describe ".seal and .open_sealed" do
    it "opens a sealed data key with the matching private key" do
      data_key = described_class.random_key
      sealed = described_class.seal(data_key, public_key:, aad: "verification:1")

      expect(described_class.open_sealed(sealed, private_key:, aad: "verification:1")).to eq(data_key)
    end

    it "seals the same value differently each time" do
      data_key = described_class.random_key

      expect(described_class.seal(data_key, public_key:, aad: "a")).not_to eq(described_class.seal(data_key, public_key:, aad: "a"))
    end

    it "refuses another private key" do
      sealed = described_class.seal(described_class.random_key, public_key:, aad: "verification:1")
      other = described_class.generate_key_pair.first

      expect { described_class.open_sealed(sealed, private_key: other, aad: "verification:1") }.to raise_error(described_class::Error)
    end

    it "refuses other additional data, so a sealed key can't move to another verification" do
      sealed = described_class.seal(described_class.random_key, public_key:, aad: "verification:1")

      expect { described_class.open_sealed(sealed, private_key:, aad: "verification:2") }.to raise_error(described_class::Error)
    end

    it "refuses a changed byte" do
      sealed = described_class.seal(described_class.random_key, public_key:, aad: "a")
      sealed.setbyte(40, sealed.getbyte(40) ^ 1)

      expect { described_class.open_sealed(sealed, private_key:, aad: "a") }.to raise_error(described_class::Error)
    end
  end

  describe ".encrypt and .decrypt" do
    it "round-trips an image and refuses another key" do
      key = described_class.random_key
      blob = described_class.encrypt("image bytes", key:, aad: "verification:1")

      expect(described_class.decrypt(blob, key:, aad: "verification:1")).to eq("image bytes")
      expect { described_class.decrypt(blob, key: described_class.random_key, aad: "verification:1") }.to raise_error(described_class::Error)
    end
  end

  describe ".key_pair?" do
    it "is true only for the matching key pair" do
      expect(described_class.key_pair?(private_key, public_key)).to be(true)
      expect(described_class.key_pair?(described_class.generate_key_pair.first, public_key)).to be(false)
      expect(described_class.key_pair?("short", public_key)).to be(false)
    end
  end

  describe "the browser formats" do
    let(:vectors) { JSON.parse(Rails.root.join("spec/fixtures/files/key_custody/browser_vectors.json").read) }

    it "derives the public key of a key pair made by the browser (WebCrypto JWK)" do
      pair = vectors["browser_key_pair"]

      expect(Base64.strict_encode64(described_class.public_key_for([pair["private_key_hex"]].pack("H*")))).to eq(pair["public_key"])
    end

    it "derives the same seal public key from a PRF output as the browser" do
      vector = vectors["seal_key"]
      private_key = described_class.seal_private_key(Base64.urlsafe_decode64(vector["prf"]))

      expect(Base64.strict_encode64(described_class.public_key_for(private_key))).to eq(vector["seal_public_key"])
    end

    it "opens a share that the browser sealed (sealShare in Node 22 WebCrypto)" do
      vector = vectors["browser_sealed"]
      private_key = described_class.seal_private_key(Base64.urlsafe_decode64(vector["prf"]))

      share = described_class.open_share(Base64.urlsafe_decode64(vector["sealed"]), private_key:, aad: vector["aad"])

      expect(share).to eq(Base64.urlsafe_decode64(vector["share"]))
      expect { described_class.open_share(Base64.urlsafe_decode64(vector["sealed"]), private_key:, aad: "#{vector['aad']}x") }
        .to raise_error(described_class::Error)
    end

    it "gives the share digest that the browser test checks" do
      vector = vectors["digest"]
      share = Base64.urlsafe_decode64(vector["share"])

      expect(described_class.share_digest(share, public_key: Base64.strict_decode64(vector["public_key"]))).to eq(vector["hex"])
    end
  end

  describe ".seal_share" do
    it "seals a share to a seal public key, and only that key and that aad open it" do
      private_key = described_class.seal_private_key(SecureRandom.random_bytes(32))
      share = SecureRandom.random_bytes(33)

      sealed = described_class.seal_share(share, public_key: described_class.public_key_for(private_key), aad: "a|1")

      expect(sealed.bytesize).to eq(KeyCustody::Ceremony::SEALED_SHARE_BYTES)
      expect(described_class.open_share(sealed, private_key:, aad: "a|1")).to eq(share)
      expect { described_class.open_share(sealed, private_key:, aad: "a|2") }.to raise_error(described_class::Error)
      expect { described_class.open_share(sealed, private_key: described_class.seal_private_key("x" * 32), aad: "a|1") }
        .to raise_error(described_class::Error)
      # A sealed data key and a sealed share use different HKDF labels.
      expect { described_class.open_sealed(sealed, private_key:, aad: "a|1") }.to raise_error(described_class::Error)
    end
  end

  describe ".share_digest" do
    it "binds the digest to the key set" do
      share = SecureRandom.random_bytes(33)

      expect(described_class.share_digest(share, public_key:)).to match(/\A\h{64}\z/)
      expect(described_class.share_digest(share, public_key:))
        .not_to eq(described_class.share_digest(share, public_key: described_class.generate_key_pair.last))
    end
  end

  describe "the sealed break-glass handoff" do
    let(:vectors) { JSON.parse(Rails.root.join("spec/fixtures/files/key_custody/handoff_vectors.json").read) }

    def b64(value) = Base64.strict_decode64(value)

    it "opens the vector that the browser test opens (spec/javascript/break_glass_handoff.test.js)" do
      data_key = described_class.open_sealed(b64(vectors["sealed_key"]), private_key: b64(vectors["private_key"]),
                                                                          aad: vectors["handoff_aad"], info: described_class::HANDOFF_SEAL_INFO)

      expect(data_key).to eq(b64(vectors["data_key"]))
      expect(described_class.decrypt(b64(vectors["ciphertext"]), key: data_key, aad: vectors["image_aad"])).to eq(b64(vectors["image"]))
    end

    it "uses its own label: a handoff blob does not open as a sealed data key or share" do
      expect do
        described_class.open_sealed(b64(vectors["sealed_key"]), private_key: b64(vectors["private_key"]), aad: vectors["handoff_aad"])
      end.to raise_error(described_class::Error)
    end
  end

  describe ".wipe" do
    it "overwrites the string in place" do
      secret = +"secret"

      described_class.wipe(secret, nil)

      expect(secret).to eq("")
    end
  end
end
