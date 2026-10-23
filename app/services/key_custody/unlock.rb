# frozen_string_literal: true

# Rebuilds a master private key from shares, in memory, for one block (see
# KeyCustody).
#
#   KeyCustody::Unlock.with_master_key(key_set, shares) do |private_key|
#     # open one data key
#   end
#
# The rebuilt key must give the key set's public key. A wrong share gives a
# wrong key, so this check refuses it. After the block, the shares and the
# key are overwritten (best effort, see Crypto.wipe).
module KeyCustody
  module Unlock
    module_function

    def with_master_key(key_set, shares)
      raise Refused, "#{key_set.threshold} shares are needed." if shares.size < key_set.threshold

      private_key = Shamir.combine(shares)
      unless Crypto.key_pair?(private_key, key_set.public_key_bytes)
        raise Refused, "The shares do not rebuild the master key of #{key_set.public_id}."
      end

      yield private_key
    rescue Shamir::Error => e
      raise Refused, "The shares can't be combined: #{e.message}."
    ensure
      Crypto.wipe(private_key, *shares)
    end
  end
end
