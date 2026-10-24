# frozen_string_literal: true

# A key holder lost one hardware key (see KeyCustody and docs/KYC.md).
#
# 1. The holder (or an owner) revokes the lost key (Enrollment.revoke!).
# 2. The holder enrolls a new key and registers its seal public key, on
#    their own computer (Enrollment.enroll! and register_seal_key!).
# 3. On the same computer, the holder touches the remaining key: the browser
#    opens the share with that key's seal private key, checks its digest,
#    and seals it to the new key's seal public key. It sends the new sealed
#    share and the assertion of the remaining key (rewrap!). The share itself
#    is not sent, and the new key needs no touch here.
#
# Logged, and the board is told. A holder who lost both keys can't do this:
# their set is compromised and must be rotated (a new ceremony).
module KeyCustody
  module Recovery
    module_function

    # The active hardware keys that open this share.
    def keys_for(share)
      return [] if share.nil? || share.holder_id.nil?

      IdentityHardwareKey.active.where(user_id: share.holder_id)
                         .joins(:wrapped_shares).where(key_custody_wrapped_shares: { share_id: share.id }).distinct.to_a
    end

    # The keys of the user with no sealed copy of this share yet.
    def unwrapped_keys_for(share)
      IdentityHardwareKey.active.where(user_id: share.holder_id).where.not(id: keys_for(share).map(&:id)).to_a
    end

    # The options for the rewrap: one challenge for a key that opens the
    # share (with PRF on its seal salt), the sealed copies, and the new key's
    # seal public key and aad.
    def options(user, new_key:)
      share = rewrap_share!(user, new_key)
      challenge = Assertions.issue!(user:, purpose: "rewrap", subject: new_key.public_id)
      old_keys = keys_for(share)
      {
        key_set_id: share.key_set.public_id,
        public_key: share.key_set.public_key,
        digest: share.digest,
        old: Assertions.request_options(challenge, keys: old_keys, prf: old_keys.to_h { |key| [key.external_id, { first: key.seal_salt }] })
                       .merge(wrapped: old_keys.to_h { |key| [key.external_id, key.wrapped_shares.find_by!(share:).blob] }),
        new: { credential_id: new_key.external_id, seal_public_key: new_key.seal_public_key,
               aad: KeyCustodyWrappedShare.aad(key_set: share.key_set, holder: user, hardware_key_external_id: new_key.external_id,
                                               x: share.x)
}
      }
    end

    # Stores the share sealed to the new key. old_credential is an assertion
    # from a key that opens the share, for the rewrap challenge.
    def rewrap!(user, new_key:, old_credential:, sealed:)
      share = rewrap_share!(user, new_key)
      raise Refused, "The sealed share is not valid." unless Ceremony.sealed_shape?(sealed)

      Assertions.verify!(old_credential, user:, purpose: "rewrap", subject: new_key.public_id, keys: keys_for(share))

      event = nil
      KeyCustodyWrappedShare.transaction do
        share.wrapped_shares.create!(hardware_key: new_key, sealed: sealed.to_s)
        event = KeyCustodyEvent.record!(:share_rewrapped, actor: user, subject: user, key_set: share.key_set,
                                                          hardware_key_id: new_key.public_id)
      end
      KeyCustody.notify_board(event)
      event
    rescue ActiveRecord::RecordInvalid => e
      raise Refused, e.record.errors.full_messages.to_sentence
    end

    def rewrap_share!(user, new_key)
      raise Refused, "Only a key holder can wrap their share." unless KeyCustody.holder?(user)
      raise Refused, "The new key must be one of your active keys." unless new_key.user_id == user.id && new_key.active?
      raise Refused, "Set up the seal key of the new key first, on your own computer." unless new_key.sealable?

      share = KeyCustody.current_key_set&.share_for(user)
      raise Refused, "You hold no share of the current key set." if share.nil?
      raise Refused, "This key already holds your share." if keys_for(share).include?(new_key)
      raise Refused, "No other key of yours opens your share. Ask for a rotation." if keys_for(share).empty?

      share
    end
  end
end
