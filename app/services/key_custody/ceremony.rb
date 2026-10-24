# frozen_string_literal: true

# The key ceremony: it makes a new key set (see KeyCustody and docs/KYC.md).
# It runs at the first setup and at each rotation. One holder (the operator)
# runs it on a clean computer. The other holders watch on a call. Nobody sends
# a hardware key or brings it to another person's computer.
#
# Before it, each holder enrolled their keys on their own computer and
# registered each key's seal public key (Enrollment.register_seal_key!).
#
# 1. start!: Weave issues one challenge for the operator and lists the
#    holders, their keys and each key's seal public key.
# 2. In the ceremony page, the operator's browser makes the master key pair
#    (X25519, WebCrypto) and splits the private key into one share for each
#    holder (the audited "shamir-secret-sharing" library).
# 3. The browser seals each share to each seal public key of its holder
#    (X25519 + HKDF-SHA256 + AES-256-GCM, with aad that binds the key set,
#    the holder, the credential and the share x). No key touches it.
# 4. complete!: the browser sends the public key, and for each share its x
#    value, its digest and the sealed copies, with one assertion from the
#    operator's own key. It then overwrites the private key and the shares.
#    The same assertion asks PRF on the seal salt of the operator's key, so
#    the browser opens the operator's own just-sealed share and sends it as
#    the operator's activation share (one touch). The other holders still
#    activate on their own computers.
#
# The plaintext master key exists only in the memory of the ceremony page,
# for the length of the ceremony. Weave gets only the public key and the
# sealed shares. The new set is pending: it becomes active when every holder
# opens their share on their own computer and submits it (Activation), which
# proves each share.
module KeyCustody
  module Ceremony
    SUBJECT_PREFIX = "ceremony-"
    # A sealed share: version, ephemeral public key, nonce, the 33 share bytes
    # and the tag.
    SEALED_SHARE_BYTES = 1 + Crypto::KEY_BYTES + Crypto::NONCE_BYTES + Crypto::KEY_BYTES + 1 + Crypto::TAG_BYTES

    module_function

    # The operator is a key holder: the ceremony needs one touch of their own
    # hardware key.
    def can_run?(user) = KeyCustody.holder?(user) && user.identity_hardware_keys.active.exists?

    # An owner or a key holder can throw away a pending set.
    def can_discard?(user) = user.present? && (user.owner? || KeyCustody.holder?(user))

    # Why the ceremony can't start now, or nil.
    def blocker
      holders = KeyCustody.holders.to_a
      if holders.size != KeyCustody.share_count
        return "There are #{holders.size} key holders. The ceremony needs exactly #{KeyCustody.share_count}."
      end

      short = holders.reject { |holder| holder.identity_hardware_keys.sealable.count == VerificationSettings.hardware_keys_per_holder }
      if short.any?
        return "Each key holder must have #{VerificationSettings.hardware_keys_per_holder} active hardware keys with a seal key first " \
               "(set up on their own computer): #{short.map(&:full_name).to_sentence}."
      end

      pending = KeyCustody.pending_key_set
      return "Key set #{pending.public_id} waits for activation. Activate it or discard it first." if pending && pending.compromised_at.nil?

      nil
    end

    def start!(by:)
      raise Refused, "Only a key holder with a hardware key can run the ceremony." unless can_run?(by)

      reason = blocker
      raise Refused, reason if reason

      subject = "#{SUBJECT_PREFIX}#{SecureRandom.hex(8)}"
      challenge = Assertions.issue!(user: by, purpose: "ceremony", subject:)
      KeyCustodyEvent.record!(:ceremony_started, actor: by, ceremony: subject)
      holders = KeyCustody.holders.includes(:identity_hardware_keys).to_a
      {
        ceremony: subject,
        threshold: KeyCustody.threshold,
        share_count: KeyCustody.share_count,
        rotation_of: KeyCustody.current_key_set&.public_id,
        holders: holders.map do |holder|
          { id: holder.public_id, name: holder.full_name,
            keys: holder.identity_hardware_keys.select(&:sealable?).map do |key|
              { id: key.external_id, label: key.label, seal_public_key: key.seal_public_key }
            end
}
        end,
        operator_id: by.public_id,
        # One touch: the operator's own key. PRF on its seal salt opens the
        # operator's own sealed share, which becomes their activation share.
        request: Assertions.request_options(challenge, keys: by.identity_hardware_keys.active.to_a,
                                                       prf: by.identity_hardware_keys.active.select(&:sealable?)
                                                              .to_h { |key| [key.external_id, { first: key.seal_salt }] })
      }
    end

    # shares: [{ holder_id:, x:, digest:, wrapped: [{ credential_id:, sealed: }] }]
    # credential: one assertion of the operator's own key for the ceremony
    # challenge.
    # operator_share: the operator's own share (Base64url), opened in the
    # browser from its sealed copy with the PRF output of that assertion.
    # When it matches the operator's digest, it is the operator's activation
    # share (Activation.give_share!). Optional: without it, the operator
    # activates like the other holders.
    def complete!(by:, ceremony:, public_key:, shares:, credential:, operator_share: nil)
      raise Refused, "Only a key holder with a hardware key can run the ceremony." unless can_run?(by)

      challenge = KeyCustodyChallenge.usable.find_by(user: by, purpose: "ceremony", subject: ceremony.to_s)
      raise Refused, "The ceremony is unknown, expired or already used. Start again." if challenge.nil?

      reason = blocker
      raise Refused, reason if reason

      public_key_bytes = decode_public_key(public_key)
      entries = check_shares!(shares)
      operator_bytes = check_operator_share!(operator_share, by, entries, public_key_bytes) if operator_share.present?
      Assertions.verify!(credential, user: by, purpose: "ceremony", subject: challenge.subject,
                                     keys: by.identity_hardware_keys.active.to_a, consume: false)

      key_set = nil
      event = nil
      KeyCustodyKeySet.transaction do
        raise Refused, "The ceremony is already used. Start again." unless challenge.consume!

        key_set = KeyCustodyKeySet.create!(public_key: Base64.strict_encode64(public_key_bytes), threshold: KeyCustody.threshold,
                                           share_count: KeyCustody.share_count, status: "pending", created_by: by,
                                           rotated_from: KeyCustody.current_key_set)
        entries.each do |entry|
          share = key_set.shares.create!(holder: entry[:holder], x: entry[:x], digest: entry[:digest])
          entry[:wrapped].each do |wrapped|
            share.wrapped_shares.create!(hardware_key: wrapped[:key], sealed: wrapped[:sealed])
          end
        end
        event = KeyCustodyEvent.record!(:ceremony_completed, actor: by, key_set:, ceremony: challenge.subject,
                                                             share_count: key_set.share_count, threshold: key_set.threshold,
                                                              holder_ids: entries.map { |entry| entry[:holder].public_id },
                                                              rotation_of: key_set.rotated_from&.public_id)
      end
      KeyCustody.notify_board(event)
      Activation.give_share!(by, key_set, :new, operator_bytes, via: "ceremony") if operator_bytes
      key_set
    rescue ActiveRecord::RecordInvalid => e
      raise Refused, e.record.errors.full_messages.to_sentence
    ensure
      Crypto.wipe(operator_bytes)
    end

    # The operator's own share must match the digest of their entry.
    def check_operator_share!(operator_share, by, entries, public_key_bytes)
      bytes = KeyCustody.decode_share(operator_share)
      entry = entries.find { |candidate| candidate[:holder].id == by.id }
      digest = Crypto.share_digest(bytes, public_key: public_key_bytes)
      unless entry && OpenSSL.fixed_length_secure_compare(digest, entry[:digest])
        Crypto.wipe(bytes)
        raise Refused, "The operator's share does not match its digest."
      end

      bytes
    end

    # An owner or a key holder throws away a pending set (for example after
    # a failed activation, or when the key holders changed). One person can
    # do it, so the board gets an email each time.
    def discard!(key_set, by:, reason:)
      raise Refused, "Only an owner or a key holder can discard a key set." unless can_discard?(by)
      raise Refused, "Only a pending key set can be discarded." unless key_set.pending?
      raise Refused, "Write why the key set is discarded." if reason.blank?

      event = nil
      KeyCustodyKeySet.transaction do
        key_set.update!(status: "retired", retired_at: Time.current)
        KeyCustodyWrappedShare.where(share_id: key_set.shares.select(:id)).delete_all
        PendingShares.discard_prefix("activate:#{key_set.id}:")
        event = KeyCustodyEvent.record!(:key_set_discarded, actor: by, key_set:, reason: reason.to_s.strip)
      end
      KeyCustody.notify_board(event)
      true
    end

    def decode_public_key(value)
      bytes = Base64.strict_decode64(value.to_s)
      raise Refused, "The public key must be 32 bytes." unless bytes.bytesize == Crypto::KEY_BYTES
      raise Refused, "This public key is already in use." if KeyCustodyKeySet.exists?(public_key: Base64.strict_encode64(bytes))

      bytes
    rescue ArgumentError
      raise Refused, "The public key is not valid Base64."
    end

    # Checks that there is one share for each key holder, with distinct x
    # values, and one sealed copy for each of the holder's sealable keys.
    def check_shares!(shares)
      raise Refused, "No shares were sent." unless shares.is_a?(Array)

      holders = KeyCustody.holders.includes(:identity_hardware_keys).index_by(&:public_id)
      entries = shares.map { |share| check_share!(share.to_h.with_indifferent_access, holders) }
      raise Refused, "There must be one share for each key holder." unless entries.map { |entry| entry[:holder].id }.sort == holders.values.map(&:id).sort
      raise Refused, "Two shares have the same x value." if entries.map { |entry| entry[:x] }.uniq.size != entries.size

      entries
    end

    def check_share!(share, holders)
      holder = holders[share[:holder_id].to_s]
      raise Refused, "A share names a person who is not a key holder." if holder.nil?

      x = Integer(share[:x].to_s, exception: false)
      raise Refused, "A share has an x value outside 1 to 255." unless x && (1..255).cover?(x)
      raise Refused, "A share digest is not valid." unless share[:digest].to_s.match?(/\A\h{64}\z/)

      keys = holder.identity_hardware_keys.select(&:sealable?).index_by(&:external_id)
      wrapped = Array(share[:wrapped]).map do |item|
        item = item.to_h.with_indifferent_access
        key = keys[item[:credential_id].to_s]
        raise Refused, "A sealed share names a key that is not an active key of #{holder.full_name} with a seal key." if key.nil?
        raise Refused, "A sealed share is not valid." unless sealed_shape?(item[:sealed])

        { key:, sealed: item[:sealed].to_s }
      end
      unless wrapped.map { |item| item[:key].id }.sort == keys.values.map(&:id).sort
        raise Refused, "#{holder.full_name}'s share must be sealed once for each of their active keys."
      end

      { holder:, x:, digest: share[:digest].to_s.downcase, wrapped: }
    end

    def sealed_shape?(value)
      bytes = Base64.urlsafe_decode64(value.to_s)
      bytes.bytesize == SEALED_SHARE_BYTES && bytes.getbyte(0) == Crypto::SEAL_VERSION
    rescue ArgumentError
      false
    end
  end
end
