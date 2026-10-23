# frozen_string_literal: true

# Activating a pending key set (see KeyCustody and docs/KYC.md).
#
# After a ceremony, EVERY holder (all share_count, 3) submits their new share
# with a hardware key, from their own session. When all new shares wait,
# Weave checks each share on its own: every combination of threshold shares
# (each pair) must rebuild the new master key that matches the new public
# key. So each holder's share is proven to work before any image is sealed
# to the set. Decryption still needs only threshold shares (2 of 3).
#
# A rotation (the set has rotated_from) also needs all new shares, and a
# threshold of shares of the old set. One touch of a hardware key gives both:
# its seal private key opens every share sealed to it. Then, in one transaction, Weave:
#
# 1. rebuilds the old master key in memory and checks it;
# 2. opens each data key sealed to the old set and seals it to the new
#    public key (images live at most 7 days, so there are few);
# 3. retires the old set and deletes its wrapped shares, so the old shares
#    are useless;
# 4. makes the new set active, and wipes the old key.
#
# A holder who lost both keys gives only their new share. A removed holder
# is no longer a key holder, so they can't take part.
module KeyCustody
  module Activation
    module_function

    def can_submit?(user, key_set)
      KeyCustody.holder?(user) && key_set.pending? && key_set.compromised_at.nil? &&
        (key_set.share_for(user) || key_set.rotated_from&.share_for(user)).present?
    end

    # The options for the assertion: the user's keys that open the new share
    # or the old share, with each key's seal salt (PRF) and the sealed
    # copies. One PRF output gives the key's seal private key, which opens
    # every share sealed to that key, so one touch opens the new and the old
    # share.
    def options(user, key_set)
      raise Refused, "You can't take part in the activation of #{key_set.public_id}." unless can_submit?(user, key_set)

      new_share = key_set.share_for(user)
      old_share = key_set.rotated_from&.share_for(user)
      keys = (Recovery.keys_for(new_share) + Recovery.keys_for(old_share)).uniq
      challenge = Assertions.issue!(user:, purpose: "activate", subject: key_set.public_id)
      prf = {}
      wrapped = {}
      keys.each do |key|
        new_wrapped = new_share && key.wrapped_shares.find_by(share: new_share)
        old_wrapped = old_share && key.wrapped_shares.find_by(share: old_share)
        prf[key.external_id] = { first: key.seal_salt }
        wrapped[key.external_id] = { new: new_wrapped&.blob, old: old_wrapped&.blob }
      end
      {
        key_set_id: key_set.public_id,
        rotation_of: key_set.rotated_from&.public_id,
        request: Assertions.request_options(challenge, keys:, prf:),
        wrapped:
      }
    end

    # Takes the user's new share and, for a rotation, their old share.
    # Returns :waiting or :activated.
    def submit!(user, key_set, credential:, new_share: nil, old_share: nil)
      raise Refused, "You can't take part in the activation of #{key_set.public_id}." unless can_submit?(user, key_set)

      new_bytes = new_share.present? ? KeyCustody.decode_share(new_share) : nil
      old_bytes = old_share.present? ? KeyCustody.decode_share(old_share) : nil
      raise Refused, "Send at least one share." if new_bytes.nil? && old_bytes.nil?

      old_set = key_set.rotated_from
      new_record = key_set.share_for(user)
      old_record = old_set&.share_for(user)
      raise Refused, "This is not your share of #{key_set.public_id}." if new_bytes && !new_record&.matches?(new_bytes)
      raise Refused, "This is not your share of #{old_set&.public_id}." if old_bytes && !old_record&.matches?(old_bytes)

      keys = (Recovery.keys_for(new_record) + Recovery.keys_for(old_record)).uniq
      Assertions.verify!(credential, user:, purpose: "activate", subject: key_set.public_id, keys:)

      give_share!(user, key_set, :new, new_bytes) if new_bytes
      give_share!(user, key_set, :old, old_bytes) if old_bytes
      return :waiting unless ready?(key_set)

      activate!(key_set, by: user)
      :activated
    ensure
      Crypto.wipe(new_bytes, old_bytes)
    end

    # Puts a checked share in the waiting list and logs it (share_given), so
    # the log shows who gave a share and who is still missing. which is :new
    # or :old. via is "activation" or "ceremony" (the operator's one touch).
    def give_share!(user, key_set, which, bytes, via: "activation")
      PendingShares.put(memory_key(key_set, which), user.id, bytes)
      KeyCustodyEvent.record!(:share_given, actor: user, subject: user, key_set: which == :old ? key_set.rotated_from : key_set,
                                            share: which.to_s, via:, activation_of: key_set.public_id)
    end

    # The holders whose new share waits now.
    def waiting_holder_ids(key_set) = PendingShares.holder_ids(memory_key(key_set, :new))

    # The number of shares that wait now: { new: n, old: n }.
    def progress(key_set)
      { new: PendingShares.holder_ids(memory_key(key_set, :new)).size,
        old: PendingShares.holder_ids(memory_key(key_set, :old)).size
}
    end

    # Every holder gave their new share, and (for a rotation) a threshold
    # of holders gave their old share.
    def ready?(key_set)
      counts = progress(key_set)
      return false if counts[:new] < key_set.share_count

      key_set.rotated_from.nil? || counts[:old] >= key_set.rotated_from.threshold
    end

    # Takes the shares out of memory under a lock on the key sets, so two
    # submissions at the same time activate once. Returns the key set.
    def activate!(key_set, by:)
      old_set = key_set.rotated_from
      new_shares = []
      old_shares = []
      rewrapped = 0
      events = []

      KeyCustodyKeySet.transaction do
        old_set&.lock!
        key_set.lock!
        return key_set if key_set.active?
        raise Refused, "#{key_set.public_id} is no longer pending." unless key_set.pending? && key_set.compromised_at.nil?
        raise Refused, "#{old_set.public_id} is not the current key set." if old_set && !old_set.current?
        return key_set unless ready?(key_set)

        new_shares = PendingShares.take(memory_key(key_set, :new)).values
        old_shares = old_set ? PendingShares.take(memory_key(key_set, :old)).values : []
        prove_each_share!(key_set, new_shares)
        if old_set
          unlock!(old_set, old_shares) do |old_private_key|
            rewrapped = IdDocumentVault.rewrap_all!(old_set, old_private_key, key_set)
          end
          old_set.update!(status: "retired", retired_at: Time.current)
          KeyCustodyWrappedShare.where(share_id: old_set.shares.select(:id)).delete_all
        end
        key_set.update!(status: "active", activated_at: Time.current)
        events << KeyCustodyEvent.record!(:key_set_activated, actor: by, key_set:)
        if old_set
          events << KeyCustodyEvent.record!(:data_keys_rewrapped, actor: by, key_set:, rewrapped:, old_key_set_id: old_set.public_id)
          events << KeyCustodyEvent.record!(:key_set_retired, actor: by, key_set: old_set, replaced_by: key_set.public_id)
          events << KeyCustodyEvent.record!(:rotation_completed, actor: by, key_set:, rewrapped:, old_key_set_id: old_set.public_id)
        end
      end
      # For a rotation, the board gets the rotation email, not a second one.
      events.each { |event| KeyCustody.notify_board(event) unless event.kind == "key_set_activated" && old_set }
      key_set
    rescue UnlockFailed => e
      # The transaction rolled back. The failure is logged after it.
      KeyCustody.notify_board(KeyCustodyEvent.record!(:unlock_failed, actor: by, key_set: e.key_set, reason: e.message, activation: true))
      raise
    ensure
      Crypto.wipe(*new_shares, *old_shares)
    end

    # Each combination of threshold shares must rebuild the master key, so
    # every share is proven, not only the first pair. Unlock wipes what it
    # gets, so it gets copies.
    def prove_each_share!(key_set, shares)
      raise UnlockFailed.new("Every holder must give their share of #{key_set.public_id}.", key_set:) if shares.size < key_set.share_count

      shares.combination(key_set.threshold).each do |combination|
        unlock!(key_set, combination.map(&:dup)) { |_private_key| nil }
      end
    end

    def unlock!(key_set, shares, &)
      Unlock.with_master_key(key_set, shares, &)
    rescue Refused, Crypto::Error => e
      raise UnlockFailed.new(e.message, key_set:)
    end

    def memory_key(key_set, which) = "activate:#{key_set.id}:#{which}"

  end
end
