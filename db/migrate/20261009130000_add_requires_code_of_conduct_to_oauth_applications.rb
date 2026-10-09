# frozen_string_literal: true

class AddRequiresCodeOfConductToOauthApplications < ActiveRecord::Migration[8.1]
  def change
    # Every app requires the code of conduct unless an admin opts it out (see
    # AppAccess).
    add_column :oauth_applications, :requires_code_of_conduct, :boolean, default: true, null: false
  end
end
