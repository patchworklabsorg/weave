# frozen_string_literal: true

class AddVerificationToGuardianConsents < ActiveRecord::Migration[8.1]
  def change
    # A stronger check than the email link: an admin has a signed guardian
    # form and spoke with the guardian (see GuardianConsent#verified?). Apps
    # read it as `guardian_verified` in the directory API.
    add_column :guardian_consents, :verified_at, :datetime
    add_column :guardian_consents, :verification_note, :text
    # guardian_consents is new in this release and still empty, so the index
    # and foreign key lock nothing.
    safety_assured do
      add_reference :guardian_consents, :verified_by, foreign_key: { to_table: :users, on_delete: :nullify }
    end
  end

end
