# frozen_string_literal: true

module DemographicsVault
  # Seals a payload so that only the holder of the private key can open it.
  #
  # Hybrid encryption with the Ruby standard library: a random AES-256-GCM key
  # encrypts the payload, and RSA-OAEP (SHA-256) wraps that key with the
  # public key. The payload is padded to a fixed size first, so the length of
  # an envelope says nothing about the answers in it.
  #
  # Lockbox is not used here because Lockbox keys are symmetric: the app that
  # writes a Lockbox field can also read it, which is what the vault must
  # prevent.
  module Envelope
    VERSION = 1
    AAD = "weave-demographics-v1"
    PADDED_SIZE = 2048
    CIPHER = "aes-256-gcm"
    OAEP = { rsa_padding_mode: "oaep", rsa_oaep_md: "sha256", rsa_mgf1_md: "sha256" }.freeze

    class TooLarge < StandardError; end

    # Raised when an envelope can't be opened: wrong key, or changed data.
    class Unreadable < StandardError; end

    class << self
      # size is the padded size in bytes. aad names what the envelope holds,
      # so an envelope of one kind can't be opened as another.
      def seal(payload, public_key, size: PADDED_SIZE, aad: AAD)
        json = payload.to_json
        raise TooLarge, "Payload is over #{size} bytes" if json.bytesize > size

        data_key = SecureRandom.random_bytes(32)
        iv = SecureRandom.random_bytes(12)
        cipher = OpenSSL::Cipher.new(CIPHER).encrypt
        cipher.key = data_key
        cipher.iv = iv
        cipher.auth_data = aad
        ciphertext = cipher.update(json.ljust(size)) + cipher.final

        {
          "v"   => VERSION,
          "kid" => key_id(public_key),
          "k"   => encode(public_key.encrypt(data_key, OAEP)),
          "iv"  => encode(iv),
          "tag" => encode(cipher.auth_tag),
          "ct"  => encode(ciphertext)
        }.to_json
      end

      # Needs the private key. Only DemographicsVault::Reader calls this.
      def open(envelope, private_key, aad: AAD)
        parts = JSON.parse(envelope)
        raise Unreadable, "Unknown envelope version" unless parts["v"] == VERSION

        data_key = private_key.decrypt(decode(parts["k"]), OAEP)
        cipher = OpenSSL::Cipher.new(CIPHER).decrypt
        cipher.key = data_key
        cipher.iv = decode(parts["iv"])
        cipher.auth_tag = decode(parts["tag"])
        cipher.auth_data = aad
        JSON.parse(cipher.update(decode(parts["ct"])) + cipher.final)
      rescue OpenSSL::PKey::PKeyError, OpenSSL::Cipher::CipherError, JSON::ParserError, ArgumentError, TypeError
        raise Unreadable, "The envelope can't be opened with this key"
      end

      # A short name for a key pair, from the public key. Stored next to each
      # envelope, so a key change shows which envelopes need the old key.
      def key_id(key) = OpenSSL::Digest::SHA256.hexdigest(key.public_to_der).first(16)

      private

      def encode(bytes) = Base64.strict_encode64(bytes)

      def decode(text) = Base64.strict_decode64(text.to_s)

    end
  end
end
