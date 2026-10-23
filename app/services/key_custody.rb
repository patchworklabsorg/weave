# frozen_string_literal: true

# Key custody of stored ID images (locked by Jasper on 2026-10-12, see
# docs/KYC.md, "Key custody").
#
# - Each ID image is encrypted with a fresh random data key. The data key is
#   sealed to the master public key (IdDocumentVault), so sealing needs no
#   key holder.
# - Weave never stores the master private key. It exists only as Shamir
#   shares (any 2 of 3), one for each key holder. Each share is wrapped in
#   the holder's browser under a key from their hardware key (WebAuthn PRF),
#   once for each of their 2 hardware keys.
# - A break-glass approval is the submission of a share with a fresh WebAuthn
#   assertion for that one request (BreakGlass.approve). The first share
#   waits in the database, encrypted with Lockbox and bound to the request,
#   for at most pending_share_minutes (PendingShares). One share alone
#   reveals nothing. When the second share comes, Weave rebuilds the master
#   key in memory, checks it against the public key, opens the one data key,
#   decrypts the one image for that response and wipes the shares, the
#   master key and the data key.
# - A new key set goes live only after every holder activates it with their
#   own share (Activation).
# - The ceremony (Ceremony) makes a key set, recovery (Recovery) replaces a
#   lost hardware key, and a rotation (a new ceremony plus Activation)
#   replaces a compromised key set.
module KeyCustody
  class Error < StandardError; end

  # The step is not allowed. The message is safe to show.
  class Refused < Error; end

  # The shares did not rebuild the master key, or the key did not open the
  # data key. Logged, and the board is told.
  class UnlockFailed < Refused
    attr_reader :key_set

    def initialize(message, key_set:)
      super(message)
      @key_set = key_set
    end

  end

  # No key set is active, so an image can't be sealed.
  class NotSetUp < Error; end

  class << self
    # The key set that new images are sealed to: active, or compromised and
    # waiting for its rotation.
    def current_key_set = KeyCustodyKeySet.current.order(:id).last

    def pending_key_set = KeyCustodyKeySet.pending.order(:id).last

    def set_up? = current_key_set.present?

    def threshold = VerificationSettings.key_custody_threshold

    def share_count = VerificationSettings.key_custody_share_count

    def holder?(user) = user.present? && user.identity_team && user.identity_key_holder

    def holders = User.identity_key_holders.order(:id)

    # Who can open the key custody page: the identity team, owners and the
    # board.
    def can_view?(user) = user.present? && (user.identity_team || user.owner? || user.is_board)

    # A share from the browser: Base64url, 32 key bytes and one x byte.
    def decode_share(value)
      bytes = Assertions.decode(value)
      raise Refused, "The share is not valid." unless bytes.bytesize == Crypto::KEY_BYTES + 1

      bytes
    rescue ArgumentError
      raise Refused, "The share is not valid."
    end

    # The WebAuthn relying party. It is the one that passkey sign-in uses
    # (config/initializers/webauthn.rb), so both features have the same RP
    # id, origin and algorithms.
    def relying_party = WebAuthn.configuration.relying_party

    # Marks a key set compromised: a holder lost both keys, or the key
    # holder set changed. The set still opens images, but the pages show a
    # warning until a rotation replaces it. The board is told.
    def mark_compromised!(key_set, reason:, actor: nil, subject: nil)
      return false if key_set.nil? || key_set.retired?

      event = nil
      key_set.with_lock do
        return false if key_set.compromised_at.present?

        # A pending set keeps its status, but it can't become active any
        # more (Activation refuses it): a new ceremony replaces it.
        status = key_set.active? ? "compromised" : key_set.status
        key_set.update!(status:, compromised_at: Time.current, compromised_reason: reason)
        event = KeyCustodyEvent.record!(:key_set_compromised, actor:, subject:, key_set:, reason:)
      end
      notify_board(event)
      true
    end

    # The subscriber of IdentityGovernance::KEY_HOLDERS_CHANGED. A changed
    # key holder set needs a rotation: a removed holder still has their
    # share, and a new holder has none.
    def key_holders_changed(user:, change:, actor: nil, **)
      reason = change.to_s == "added" ? "key_holder_added" : "key_holder_removed"
      [current_key_set, pending_key_set].compact.each do |key_set|
        mark_compromised!(key_set, reason:, actor:, subject: user)
      end
    end

    def notify_board(event)
      return unless event&.board_kind?

      User.board_members.where.not(email: nil).find_each do |member|
        KeyCustodyMailer.event(event, member).deliver_later
      end
    end

    # Why pre-review can't end, when the reason is key custody.
    def warning_for_pre_review
      "Key custody is not set up, so the image can't be sealed and pre-review can't end. Run the key ceremony first." unless set_up?
    end

    # The status line that the identity pages show.
    def warning
      key_set = current_key_set
      return "Key custody is not set up. Images can't be sealed, so pre-review can't end. Run the ceremony." if key_set.nil?
      return unless key_set.compromised?

      "The key set #{key_set.public_id} is compromised (#{key_set.compromised_reason.to_s.humanize.downcase}). " \
        "Rotate it: run a new ceremony, then all three holders activate the new one (two of them also give their old share)."
    end

  end
end
