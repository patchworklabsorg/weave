# frozen_string_literal: true

class AddReviewToGuardianConsents < ActiveRecord::Migration[8.1]
  def change
    # Signs that a consent may not come from a real parent or guardian, and an
    # admin's check of them (see GuardianConsentSignals).
    add_column :guardian_consents, :granted_fingerprint, :string
    add_column :guardian_consents, :flags, :jsonb, default: [], null: false
    add_column :guardian_consents, :reviewed_at, :datetime
    add_column :guardian_consents, :review_note, :text
    # guardian_consents is new in this release and still empty, so the index
    # and foreign key lock nothing.
    safety_assured do
      add_reference :guardian_consents, :reviewed_by, foreign_key: { to_table: :users, on_delete: :nullify }
    end
  end

end
