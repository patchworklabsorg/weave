# frozen_string_literal: true

# Deletes stored ID images when their time is up (see
# config/kyc/verification.yml):
#
# - after a pass: purge_image_days_after_pass
# - after a document problem or a failed call: purge_image_days_after_close,
#   but not while the lead reviews an escalation
# - at once when the member's account is deleted
#
# It purges the Lockbox copy and the sealed copy (see IdDocumentVault). The
# verification and its audit record stay. Running it twice deletes nothing
# new.
class PurgeVerificationDocumentsJob < ApplicationJob
  queue_as :low

  def perform
    purged = 0
    Verification.where(document_purged_at: nil).left_joins(:id_document_attachment, :sealed_document)
                .where("active_storage_attachments.id IS NOT NULL OR sealed_id_documents.id IS NOT NULL")
                .distinct.find_each do |verification|
      reason = purge_reason(verification)
      next unless reason

      Verification.transaction do
        IdDocumentVault.purge!(verification)
        verification.update!(document_purged_at: Time.current)
        VerificationEvent.record!(verification, :document_purged, reason:)
      end
      purged += 1
    end
    Rails.logger.info("Purged #{purged} ID images") if purged.positive?
  end

  private

  def purge_reason(verification)
    return "account_deleted" if verification.user_id.nil?
    return "after_pass" if verification.verified? && verification.decided_at <= VerificationSettings.purge_image_after_pass.ago
    return nil if verification.escalation_open?

    closed_at = verification.closed_at
    "after_close" if closed_at && closed_at <= VerificationSettings.purge_image_after_close.ago
  end

end
