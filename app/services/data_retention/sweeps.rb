# frozen_string_literal: true

module DataRetention
  # The daily retention sweeps (DataRetentionJob). Each one applies a window
  # from config/kyc/data_retention.yml. Running a sweep twice changes nothing
  # new.
  module Sweeps
    class << self
      def run_all
        {
          verification_audit_purged: purge_verification_audit!,
          financial_anonymized: anonymize_financial!,
          funder_records_folded: fold_expired_funder_records!,
          guardian_contacts_purged: purge_adult_guardian_contacts!,
          takeouts_expired: expire_takeouts!
        }
      end

      # Verification audit records: destroyed keep_years_after_deletion after
      # the account was deleted. The fraud-evidence hold: an attempt linked
      # to a blacklisted Knot stays while the flag stands. When the flag is
      # cleared, the normal window applies at the next run.
      def purge_verification_audit!
        cutoff = DataRetention.verification_audit_window.ago
        expired = Verification.where(user_id: nil).where(account_deleted_at: ..cutoff)
                              .left_joins(:knot).where("knots.id IS NULL OR knots.blacklisted = FALSE")
        purged = 0
        expired.find_each do |verification|
          destroy_verification!(verification)
          purged += 1
        end
        purged
      end

      # Grant disbursements: anonymized after the financial window (the
      # longer of the default and the funder's terms). The amount, the
      # program, the funder and the date stay for ever.
      def anonymize_financial!
        earliest = DataRetention.financial_keep_years.years.ago.to_date
        anonymized = 0
        GrantDisbursement.not_anonymized.where(disbursed_on: ...earliest).find_each do |disbursement|
          next unless disbursement.full_retention_ends_on < Date.current

          disbursement.anonymize!
          anonymized += 1
        end
        anonymized
      end

      # Funder-required individual records: when the funder's window closes,
      # the bands fold into the delete-time aggregates and the record goes.
      def fold_expired_funder_records!
        folded = 0
        ProgramParticipation.retention_expired.find_each do |participation|
          ProgramParticipation.transaction do
            next unless ProgramParticipation.where(id: participation.id).delete_all == 1

            DeleteTimeAggregates.add!(DeleteTimeAggregates.bands_for(participation, user: nil))
            folded += 1
          end
        end
        folded
      end

      # Guardian contact: kept until the member turns guardian_contact_until_age.
      # (The deletion pipeline removes it when the member leaves.)
      def purge_adult_guardian_contacts!
        adult_born_before = DataRetention.guardian_contact_until_age.years.ago.to_date
        ids = GuardianConsent.joins(:user).where(users: { birthday: ..adult_born_before }).ids
        return 0 if ids.empty?

        GuardianConsent.transaction do
          PaperTrail::Version.where(item_type: "GuardianConsent", item_id: ids).delete_all
          GuardianConsent.where(id: ids).delete_all
        end
      end

      # Takeout files: deleted after takeout.download_days.
      def expire_takeouts!
        expired = 0
        TakeoutRequest.where(status: "ready").where(expires_at: ..Time.current).find_each do |takeout|
          takeout.archive.purge if takeout.archive.attached?
          takeout.update!(status: "expired")
          expired += 1
        end
        expired
      end

      private

      # The audit rows are append-only for the app. This retention purge is
      # the one path that removes them, with the attempt, its break-glass
      # records and their PaperTrail rows.
      def destroy_verification!(verification)
        Verification.transaction do
          records = BreakGlassRecord.where(verification_id: verification.id)
          decryptions = BreakGlassDecryption.where(break_glass_record_id: records.select(:id))
          notices = BreakGlassNotice.where(break_glass_decryption_id: decryptions.select(:id))
          PaperTrail::Version.where(item_type: "BreakGlassNotice", item_id: notices.ids).delete_all
          PaperTrail::Version.where(item_type: "BreakGlassRecord", item_id: records.ids).delete_all
          notices.delete_all
          decryptions.delete_all
          BreakGlassApproval.where(break_glass_record_id: records.select(:id)).delete_all
          records.delete_all
          VerificationEvent.where(verification_id: verification.id).delete_all
          IdDocumentVault.purge!(verification)
          PaperTrail::Version.where(item_type: "Verification", item_id: verification.id).delete_all
          Verification.where(id: verification.id).delete_all
        end
      end

    end
  end
end
