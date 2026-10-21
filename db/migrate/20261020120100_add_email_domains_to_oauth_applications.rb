# frozen_string_literal: true

# When set, the app's `email` claim is the user's confirmed address on one of
# these domains, and users without one may not use the app. Google Workspace
# needs this: the claim must equal the person's primary Google address.
class AddEmailDomainsToOauthApplications < ActiveRecord::Migration[8.1]
  def change
    add_column :oauth_applications, :email_domains, :string, array: true, default: [], null: false
  end

end
