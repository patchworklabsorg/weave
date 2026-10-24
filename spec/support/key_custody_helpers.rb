# frozen_string_literal: true

# Helpers for key custody specs (see KeyCustody).
#
# A FakeKey is a hardware key: a WebAuthn::FakeClient with its own fake
# authenticator. The fake client does not do the PRF extension, so a FakeKey
# stubs it: the PRF output is HMAC-SHA256 of a secret that only this key
# knows, over the salt (a real YubiKey does hmac-secret the same way).
#
# The browser side is emulated in Ruby with the same steps as
# app/javascript/key_custody/crypto.js: HKDF-SHA256 of the PRF output for the
# key's seal salt gives its X25519 seal private key, and a share is sealed to
# the seal public key (KeyCustody::Crypto.seal_share).
require "webauthn/fake_client"

module KeyCustodyHelpers
  ORIGIN = "http://localhost:3000"

  class FakeKey
    attr_reader :client, :prf_secret
    attr_accessor :record

    def initialize
      @client = WebAuthn::FakeClient.new(ORIGIN)
      @prf_secret = SecureRandom.random_bytes(32)
    end

    delegate :external_id, to: :record

    def prf(salt_b64) = OpenSSL::HMAC.digest("SHA256", prf_secret, "WebAuthn PRF\0".b + b64d(salt_b64))

    def assert(challenge, user_verified: true)
      client.get(challenge:, user_verified:, allow_credentials: [external_id])
    end

    # The seal key pair of this key, as the holder's browser derives it.
    def seal_private_key = KeyCustody::Crypto.seal_private_key(prf(record.seal_salt))

    def seal_public_key = KeyCustody::Crypto.public_key_for(seal_private_key)

    # The seal public key for a salt, before the key has a record: what the
    # browser derives from the PRF output at creation (one touch).
    def seal_public_key_for(salt_b64) = KeyCustody::Crypto.public_key_for(KeyCustody::Crypto.seal_private_key(prf(salt_b64)))

    # Opens a sealed share as the browser does: { sealed:, aad: } (a Hash
    # from the options JSON, or a KeyCustodyWrappedShare).
    def open(wrapped)
      blob = wrapped.respond_to?(:blob) ? wrapped.blob : wrapped.to_h.symbolize_keys
      KeyCustody::Crypto.open_share(b64d(blob[:sealed]), private_key: seal_private_key, aad: blob[:aad])
    end

    def b64e(bytes) = Base64.urlsafe_encode64(bytes, padding: false)

    def b64d(value) = Base64.urlsafe_decode64(value)

  end

  def b64url(bytes) = Base64.urlsafe_encode64(bytes, padding: false)

  def enroll_fake_key(user, role:, prf: true, seal: true)
    fake = FakeKey.new
    options = KeyCustody::Enrollment.creation_options(user)
    credential = fake.client.create(challenge: options[:challenge], user_verified: true)
    credential["clientExtensionResults"] = { "prf" => { "enabled" => prf } }
    fake.record = KeyCustody::Enrollment.enroll!(user, credential:, role:)
    register_seal_key(user, fake) if seal
    fake
  end

  # Step 2 of enrollment, as the holder's browser does it.
  def register_seal_key(user, fake, public_key: nil)
    options = KeyCustody::Enrollment.seal_key_options(user, fake.record)
    KeyCustody::Enrollment.register_seal_key!(user, fake.record, credential: fake.assert(options[:challenge]),
                                                                 seal_public_key: Base64.strict_encode64(public_key || fake.seal_public_key))
    fake.record.reload
  end

  # A share sealed to a fake key, as the ceremony page does it.
  def seal_for(fake, share, key_set_public_key_b64:, holder:)
    stub_key_set = KeyCustodyKeySet.new(public_key: key_set_public_key_b64)
    aad = KeyCustodyWrappedShare.aad(key_set: stub_key_set, holder:, hardware_key_external_id: fake.external_id, x: share.getbyte(-1))
    b64url(KeyCustody::Crypto.seal_share(share, public_key: fake.seal_public_key, aad:))
  end

  # Three key holders, each with a primary and a backup key. Returns
  # { holder => [primary FakeKey, backup FakeKey] }.
  def key_holders_with_keys(count: 3)
    create_list(:user, count, :key_holder).index_with do |holder|
      [enroll_fake_key(holder, role: "primary"), enroll_fake_key(holder, role: "backup")]
    end
  end

  # Runs the ceremony like the browser does. Returns a CeremonyResult with
  # the pending key set, the master private key and each holder's share
  # (the spec plays the holders, so it keeps them).
  CeremonyResult = Struct.new(:key_set, :private_key, :shares, keyword_init: true)

  # operator_key picks the key that signs the operator's one assertion (a
  # spec swaps it to test a wrong key).
  # operator_share: true plays the one-touch ceremony: the browser opens the
  # operator's own sealed share with the PRF output of the assertion and
  # sends it as the operator's activation share.
  def run_ceremony(operator:, keys:, private_key: nil, operator_key: nil, operator_share: false)
    options = KeyCustody::Ceremony.start!(by: operator)
    private_key ||= KeyCustody::Crypto.generate_key_pair.first
    public_key = KeyCustody::Crypto.public_key_for(private_key)
    public_b64 = Base64.strict_encode64(public_key)
    split = KeyCustody::Shamir.split(private_key, share_count: keys.size, threshold: KeyCustody.threshold)
    shares = {}
    entries = keys.each_with_index.map do |(holder, fakes), index|
      share = split[index]
      shares[holder] = share
      {
        holder_id: holder.public_id, x: share.getbyte(-1),
        digest: KeyCustody::Crypto.share_digest(share, public_key:),
        wrapped: fakes.map do |fake|
          { credential_id: fake.external_id, sealed: seal_for(fake, share, key_set_public_key_b64: public_b64, holder:) }
        end
      }
    end
    signer = operator_key || keys.fetch(operator, nil)&.first || raise("The operator needs a fake key")
    own = operator_share ? b64url(open_own_sealed_share(signer, entries, operator, public_b64, shares[operator])) : nil
    key_set = KeyCustody::Ceremony.complete!(by: operator, ceremony: options[:ceremony], public_key: public_b64, shares: entries,
                                             credential: signer.assert(options[:request][:challenge]), operator_share: own)
    CeremonyResult.new(key_set:, private_key:, shares:)
  end

  # The operator's browser in the one-touch ceremony: it opens the share it
  # just sealed to the key that signed the assertion.
  def open_own_sealed_share(signer, entries, operator, public_b64, share)
    entry = entries.find { |item| item[:holder_id] == operator.public_id }
    sealed = entry[:wrapped].find { |item| item[:credential_id] == signer.external_id }[:sealed]
    aad = KeyCustodyWrappedShare.aad(key_set: KeyCustodyKeySet.new(public_key: public_b64), holder: operator,
                                     hardware_key_external_id: signer.external_id, x: share.getbyte(-1))
    signer.open({ sealed:, aad: })
  end

  # The holder's share, opened from its wrapped copy with this fake key,
  # like the browser does.
  def open_share(fake, key_set)
    share = key_set.share_for(fake.record.user)
    fake.open(share.wrapped_shares.find_by!(hardware_key: fake.record))
  end

  # A key holder activates a pending set (and, for a rotation, gives the old
  # share too).
  def submit_activation(holder, fake, key_set)
    options = KeyCustody::Activation.options(holder, key_set)
    new_share = opens?(fake, key_set) ? open_share(fake, key_set) : nil
    old_share = key_set.rotated_from && opens?(fake, key_set.rotated_from) ? open_share(fake, key_set.rotated_from) : nil
    KeyCustody::Activation.submit!(holder, key_set, credential: fake.assert(options[:request][:challenge]),
                                                    new_share: new_share && b64url(new_share),
                                                    old_share: old_share && b64url(old_share))
  end

  # Every holder activates the set with their first key (a new key set goes
  # live only after all of them). Returns the last outcome.
  def activate_by_all(key_set, keys)
    keys.map { |holder, fakes| submit_activation(holder, fakes.first, key_set) }.last
  end

  # Does this fake key hold a wrapped copy of its holder's share in key_set?
  def opens?(fake, key_set)
    share = key_set.share_for(fake.record.user)
    share.present? && share.wrapped_shares.exists?(hardware_key: fake.record)
  end

  # An active key set with three holders. Returns the CeremonyResult and the
  # keys.
  def setup_key_custody(operator: nil)
    keys = key_holders_with_keys
    result = run_ceremony(operator: operator || keys.keys.first, keys:)
    activate_by_all(result.key_set, keys)
    result.key_set.reload
    [result, keys]
  end

  # The fast path for specs that only need a key set to seal to: a set with
  # no holders, made in Ruby. Returns [key_set, private_key].
  def active_key_set_without_holders
    private_key, public_key = KeyCustody::Crypto.generate_key_pair
    key_set = KeyCustodyKeySet.create!(public_key: Base64.strict_encode64(public_key), threshold: 2, share_count: 3,
                                       status: "active", activated_at: Time.current)
    [key_set, private_key]
  end

  # Seals a verification's image to the current key set, like the end of
  # pre-review does.
  def seal!(verification)
    IdDocumentVault.seal!(verification)
    verification.reload
  end

  # A break-glass record granted by two key holders with their hardware
  # keys. Sets up key custody when it is not set up. Returns the record; the
  # approving holders are approvers.
  def granted_break_glass_record(verification, requester:, reason: "Fraud report: compare the document.")
    @key_custody_setup ||= setup_key_custody
    _result, keys = @key_custody_setup
    seal!(verification)
    record = BreakGlass.request(verification, by: requester, reason:, requester_public_key: browser_public_key(requester)).record
    raise "Break-glass request refused" unless record.persisted?

    keys.reject { |holder, _fakes| holder == requester || BreakGlass.lead_verifier_for_member?(holder, record) }
        .first(2).each { |holder, fakes| approve_with_key(record, holder, fakes.first).then { |r| raise r.error unless r.success? } }
    record.reload
  end

  # The one-time X25519 key pair of a requester's "browser" for break-glass
  # (see key_custody/handoff.js). The spec plays the browser, so it keeps
  # the private key. Returns [private_key, public_key] as raw bytes.
  def browser_key_pair(user) = (@browser_key_pairs ||= {})[user.id] ||= KeyCustody::Crypto.generate_key_pair

  def browser_public_key(user) = Base64.strict_encode64(browser_key_pair(user).last)

  # Opens a sealed handoff as the requester's browser does: the data key
  # with the browser's private key, then the image with the data key.
  def open_in_browser(handoff, user, private_key: browser_key_pair(user).first)
    sealed = Base64.strict_decode64(handoff.respond_to?(:sealed_key) ? handoff.sealed_key : handoff["sealed_key"])
    aad = handoff.respond_to?(:handoff_aad) ? handoff.handoff_aad : handoff["handoff_aad"]
    data_key = KeyCustody::Crypto.open_sealed(sealed, private_key:, aad:, info: KeyCustody::Crypto::HANDOFF_SEAL_INFO)
    ciphertext = handoff.respond_to?(:ciphertext) ? handoff.ciphertext : Base64.strict_decode64(handoff["ciphertext"])
    KeyCustody::Crypto.decrypt(ciphertext, key: data_key, aad: handoff.respond_to?(:image_aad) ? handoff.image_aad : handoff["image_aad"])
  end

  # A granted break-glass record that the requester opened in their
  # browser, so the decryption and its notices exist.
  def opened_break_glass_record(verification, requester:, reason: "Fraud report: compare the document.")
    record = granted_break_glass_record(verification, requester:, reason:)
    BreakGlass.open!(record, by: requester)
    record.reload
  end

  # A break-glass approval as the browser sends it.
  def approve_with_key(record, holder, fake, share: nil)
    challenge = KeyCustody::Assertions.issue!(user: holder, purpose: "break_glass", subject: record.public_id)
    key_set = record.verification.sealed_document.key_set
    share ||= open_share(fake, key_set)
    BreakGlass.approve(record, by: holder, credential: fake.assert(challenge.challenge), share: b64url(share))
  end
end

RSpec.configure do |config|
  config.include KeyCustodyHelpers
  config.before { KeyCustody::PendingShares.clear! }
end
