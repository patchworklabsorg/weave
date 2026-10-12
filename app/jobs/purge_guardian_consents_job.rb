# frozen_string_literal: true

# Deletes guardian consents past their retention period (see
# GuardianConsent.purgeable). The privacy policy promises these periods.
#
# It also deletes the PaperTrail versions of each consent, because they hold
# copies of the encrypted guardian name, email and signature. It uses
# delete_all, so the deletion itself leaves no version with a copy. Running it
# twice deletes nothing new.
class PurgeGuardianConsentsJob < ApplicationJob
  queue_as :low

  def perform
    ids = GuardianConsent.purgeable.ids
    return if ids.empty?

    GuardianConsent.transaction do
      PaperTrail::Version.where(item_type: "GuardianConsent", item_id: ids).delete_all
      GuardianConsent.where(id: ids).delete_all
    end
    Rails.logger.info("Purged #{ids.size} guardian consents past their retention period")
  end

end
