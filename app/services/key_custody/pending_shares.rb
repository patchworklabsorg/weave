# frozen_string_literal: true

# Shares that wait for the next share (see KeyCustody).
#
# The first holder's share waits in the key_custody_pending_shares table
# (KeyCustodyPendingShare), so every web process sees it: Weave does not
# depend on one Puma process. This is safe because one Shamir share alone
# reveals nothing about the master key. Each row:
#
# - is encrypted with Lockbox and bound to its memory key (for example
#   "break_glass:12:3"), so it opens only for that request;
# - is deleted when the shares are combined (take), on a deny (discard),
#   and after pending_share_minutes (sweep!, SweepPendingSharesJob);
# - never reaches PaperTrail, a log, a job argument or the data-category
#   matrix.
#
# take locks the rows (SELECT ... FOR UPDATE) and deletes them in the
# caller's transaction, so two web processes can't both combine the same
# shares. The callers also hold a row lock on the request or the key set.
module KeyCustody
  module PendingShares
    class << self
      # Stores share for this key and this holder. A holder's older share
      # for the same key is replaced.
      def put(key, holder_id, share, ttl: VerificationSettings.pending_share_ttl)
        KeyCustodyPendingShare.transaction do
          KeyCustodyPendingShare.where(memory_key: key, holder_id:).delete_all
          KeyCustodyPendingShare.create!(memory_key: key, holder_id:, share: KeyCustodyPendingShare.bound(key, share),
                                         expires_at: ttl.from_now)
        end
      end

      # The holders whose share still waits for this key.
      def holder_ids(key) = KeyCustodyPendingShare.live.where(memory_key: key).order(:holder_id).pluck(:holder_id)

      # Takes the live shares out of the database: { holder_id => share }.
      # The rows are locked and deleted in the caller's transaction. The
      # caller must wipe the shares (Unlock does).
      def take(key)
        KeyCustodyPendingShare.transaction do
          rows = KeyCustodyPendingShare.where(memory_key: key).lock.to_a
          KeyCustodyPendingShare.where(id: rows.map(&:id)).delete_all
          rows.select { |row| row.expires_at > Time.current }.to_h { |row| [row.holder_id, row.share_bytes] }
        end
      end

      # Drops the share of one holder for this key.
      def remove(key, holder_id) = KeyCustodyPendingShare.where(memory_key: key, holder_id:).delete_all

      def discard(key) = KeyCustodyPendingShare.where(memory_key: key).delete_all

      # Discards every key that starts with prefix.
      def discard_prefix(prefix)
        KeyCustodyPendingShare.where("memory_key LIKE ?", "#{KeyCustodyPendingShare.sanitize_sql_like(prefix)}%").delete_all
      end

      # Deletes every expired share (SweepPendingSharesJob). Returns the
      # number of shares that still wait.
      def sweep!
        KeyCustodyPendingShare.expired.delete_all
        KeyCustodyPendingShare.count
      end

      # For specs.
      def clear! = KeyCustodyPendingShare.delete_all

      def size = KeyCustodyPendingShare.live.count

    end
  end
end
