# frozen_string_literal: true

# The encryption of key custody (see KeyCustody and docs/KYC.md). Only Ruby's
# OpenSSL is used: X25519, HKDF-SHA256 and AES-256-GCM.
#
# - An ID image is encrypted with a fresh random data key (AES-256-GCM).
# - The data key is sealed to the master public key: an ephemeral X25519
#   key pair, a shared secret, HKDF-SHA256 and AES-256-GCM. Sealing needs
#   only the public key, so an upload needs no key holder.
# - Opening a sealed data key needs the master private key, which exists
#   only for a moment, in memory, after two key holders give their shares.
# - A share is sealed the same way (SHARE_SEAL_INFO) to a hardware key's
#   seal public key. The seal private key comes from the key's PRF output
#   (SEAL_KEY_INFO) and exists only in the holder's browser. Ruby makes and
#   opens these only in specs, as the browser does.
module KeyCustody
  module Crypto
    class Error < StandardError; end

    KEY_BYTES = 32
    NONCE_BYTES = 12
    TAG_BYTES = 16
    SEAL_VERSION = 1
    SEAL_INFO = "weave key custody sealed data key v1"
    # A share sealed to a hardware key's seal public key (ceremony, rewrap).
    SHARE_SEAL_INFO = "weave key custody sealed share v1"
    # HKDF info that turns a hardware key's PRF output into its X25519 seal
    # private key. The browser uses the same label (key_custody/crypto.js).
    SEAL_KEY_INFO = "weave key custody seal key v1"
    # A data key sealed to the one-time key of a break-glass requester's
    # browser (the sealed handoff, see BreakGlass). The browser uses the same
    # label (key_custody/handoff.js).
    HANDOFF_SEAL_INFO = "weave key custody handoff v1"
    DATA_VERSION = 1

    module_function

    def random_key = SecureRandom.random_bytes(KEY_BYTES)

    # A new X25519 key pair as raw bytes: [private_key, public_key]. Specs
    # and the server-side tests use it. In production the ceremony makes the
    # master key pair in the browser.
    def generate_key_pair
      key = OpenSSL::PKey.generate_key("X25519")
      [key.raw_private_key, key.raw_public_key]
    end

    def public_key_for(private_key)
      raise Error, "The private key must be #{KEY_BYTES} bytes" unless private_key&.bytesize == KEY_BYTES

      OpenSSL::PKey.new_raw_private_key("X25519", private_key).raw_public_key
    end

    # Does this private key belong to this public key? This is the check
    # after shares are combined: a wrong share gives a wrong key.
    def key_pair?(private_key, public_key)
      return false unless private_key&.bytesize == KEY_BYTES && public_key&.bytesize == KEY_BYTES

      OpenSSL.fixed_length_secure_compare(public_key_for(private_key), public_key)
    rescue OpenSSL::PKey::PKeyError
      false
    end

    # Seals plaintext (a data key) to an X25519 public key. aad binds the
    # result to its use, for example the verification it belongs to.
    #
    #   version (1) | ephemeral public key (32) | nonce (12) | ciphertext | tag (16)
    def seal(plaintext, public_key:, aad:, info: SEAL_INFO)
      raise Error, "The public key must be #{KEY_BYTES} bytes" unless public_key&.bytesize == KEY_BYTES

      ephemeral = OpenSSL::PKey.generate_key("X25519")
      ephemeral_public = ephemeral.raw_public_key
      key = seal_key(ephemeral.derive(raw_public(public_key)), ephemeral_public, public_key, info)
      nonce, ciphertext, tag = aes_encrypt(key, plaintext, aad: seal_aad(aad))
      [SEAL_VERSION].pack("C") + ephemeral_public + nonce + ciphertext + tag
    ensure
      wipe(key)
    end

    def open_sealed(sealed, private_key:, aad:, info: SEAL_INFO)
      raise Error, "The sealed value is too short" if sealed.nil? || sealed.bytesize < 1 + KEY_BYTES + NONCE_BYTES + TAG_BYTES
      raise Error, "Unknown seal version" unless sealed.getbyte(0) == SEAL_VERSION

      ephemeral_public = sealed.byteslice(1, KEY_BYTES)
      nonce = sealed.byteslice(1 + KEY_BYTES, NONCE_BYTES)
      body = sealed.byteslice(1 + KEY_BYTES + NONCE_BYTES..)
      ciphertext = body.byteslice(0, body.bytesize - TAG_BYTES)
      tag = body.byteslice(-TAG_BYTES, TAG_BYTES)
      private = OpenSSL::PKey.new_raw_private_key("X25519", private_key)
      key = seal_key(private.derive(raw_public(ephemeral_public)), ephemeral_public, private.raw_public_key, info)
      aes_decrypt(key, nonce, ciphertext, tag, aad: seal_aad(aad))
    ensure
      wipe(key)
    end

    # The X25519 seal private key of a hardware key, from its PRF output.
    def seal_private_key(prf_output)
      OpenSSL::KDF.hkdf(prf_output, salt: "", info: SEAL_KEY_INFO, length: KEY_BYTES, hash: "SHA256")
    end

    def seal_share(share, public_key:, aad:) = seal(share, public_key:, aad:, info: SHARE_SEAL_INFO)

    def open_share(sealed, private_key:, aad:) = open_sealed(sealed, private_key:, aad:, info: SHARE_SEAL_INFO)

    # Encrypts an image with a data key.
    #
    #   version (1) | nonce (12) | ciphertext | tag (16)
    def encrypt(plaintext, key:, aad:)
      nonce, ciphertext, tag = aes_encrypt(key, plaintext, aad:)
      [DATA_VERSION].pack("C") + nonce + ciphertext + tag
    end

    def decrypt(blob, key:, aad:)
      raise Error, "The encrypted value is too short" if blob.nil? || blob.bytesize < 1 + NONCE_BYTES + TAG_BYTES
      raise Error, "Unknown data version" unless blob.getbyte(0) == DATA_VERSION

      nonce = blob.byteslice(1, NONCE_BYTES)
      ciphertext = blob.byteslice(1 + NONCE_BYTES, blob.bytesize - 1 - NONCE_BYTES - TAG_BYTES)
      tag = blob.byteslice(-TAG_BYTES, TAG_BYTES)
      aes_decrypt(key, nonce, ciphertext, tag, aad:)
    end

    # SHA-256 of a share, bound to the key set. Weave stores this digest, so
    # it can refuse a wrong share before it combines anything. The share is
    # 32 random bytes and an x byte, so the digest gives away nothing.
    # The browser computes the same digest at the ceremony.
    def share_digest(share, public_key:)
      OpenSSL::Digest::SHA256.hexdigest("weave key custody share v1\0".b + public_key.b + share.b)
    end

    # Overwrites a String in place. This is best effort: Ruby can keep other
    # copies (the garbage collector moves objects, and OpenSSL and the
    # request body have their own buffers). See docs/KYC.md.
    def wipe(*values)
      values.each do |value|
        next unless value.is_a?(String) && !value.frozen?

        value.replace("\0" * value.bytesize)
        value.clear
      end
      nil
    end

    def aes_encrypt(key, plaintext, aad:)
      cipher = OpenSSL::Cipher.new("aes-256-gcm").encrypt
      cipher.key = key
      nonce = cipher.random_iv
      cipher.auth_data = aad.to_s.b
      ciphertext = cipher.update(plaintext.to_s.b) + cipher.final
      [nonce, ciphertext, cipher.auth_tag(TAG_BYTES)]
    end

    def aes_decrypt(key, nonce, ciphertext, tag, aad:)
      cipher = OpenSSL::Cipher.new("aes-256-gcm").decrypt
      cipher.key = key
      cipher.iv = nonce
      cipher.auth_tag = tag
      cipher.auth_data = aad.to_s.b
      cipher.update(ciphertext) + cipher.final
    rescue OpenSSL::Cipher::CipherError
      raise Error, "The value does not decrypt with this key"
    end

    def seal_key(shared_secret, ephemeral_public, recipient_public, info = SEAL_INFO)
      OpenSSL::KDF.hkdf(shared_secret, salt: ephemeral_public + recipient_public, info:,
                                       length: KEY_BYTES, hash: "SHA256")
    ensure
      wipe(shared_secret)
    end

    def seal_aad(aad) = "weave key custody seal v1|#{aad}"

    def raw_public(bytes) = OpenSSL::PKey.new_raw_public_key("X25519", bytes)
  end
end
