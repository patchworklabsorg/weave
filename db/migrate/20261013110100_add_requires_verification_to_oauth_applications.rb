# frozen_string_literal: true

class AddRequiresVerificationToOauthApplications < ActiveRecord::Migration[8.1]
  def change
    # Apps that give program resources (compute, servers, grant money) opt in
    # to identity verification (see AppAccess). The community is not gated, so
    # the default is off.
    add_column :oauth_applications, :requires_verification, :boolean, default: false, null: false
  end

end
