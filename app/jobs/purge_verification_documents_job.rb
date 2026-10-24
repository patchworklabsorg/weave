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
#
# US residency proof documents (see ResidencyDocumentVault) follow the same
# windows: a yes result counts as a pass, and a no result or a sent-back
# document as a close.
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
    purge_residency_documents
  end

  private

  def purge_residency_documents
    purged = 0
    ResidencyCheck.where(document_purged_at: nil).left_joins(:document_attachment, :sealed_document)
                  .where("active_storage_attachments.id IS NOT NULL OR sealed_residency_documents.id IS NOT NULL")
                  .distinct.find_each do |check|
      next unless residency_purge_due?(check)

      ResidencyCheck.transaction do
        ResidencyDocumentVault.purge!(check)
        check.update!(document_purged_at: Time.current)
      end
      purged += 1
    end
    Rails.logger.info("Purged #{purged} residency documents") if purged.positive?
  end

  def residency_purge_due?(check)
    return true if check.user_id.nil?
    return check.decided_at <= VerificationSettings.purge_image_after_pass.ago if check.decided? && check.us_resident

    closed_at = check.closed_at
    closed_at.present? && closed_at <= VerificationSettings.purge_image_after_close.ago
  end

  def purge_reason(verification)
    return "account_deleted" if verification.user_id.nil?
    return "after_pass" if verification.verified? && verification.decided_at <= VerificationSettings.purge_image_after_pass.ago
    return nil if verification.escalation_open?

    closed_at = verification.closed_at
    "after_close" if closed_at && closed_at <= VerificationSettings.purge_image_after_close.ago
  end

end
