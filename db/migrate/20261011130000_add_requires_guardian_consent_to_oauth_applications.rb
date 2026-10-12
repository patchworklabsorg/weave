# frozen_string_literal: true

class AddRequiresGuardianConsentToOauthApplications < ActiveRecord::Migration[8.1]
  def change
    # Every app requires a parent or guardian's consent for members under 18
    # unless an admin opts it out (see AppAccess).
    add_column :oauth_applications, :requires_guardian_consent, :boolean, default: true, null: false
  end

end
