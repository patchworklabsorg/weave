# frozen_string_literal: true

# The app launcher on the member dashboard, and the group that an approved
# access request adds the member to (see AccessRequest).
class AddLauncherToOauthApplications < ActiveRecord::Migration[8.1]
  def change
    # oauth_applications holds a few dozen rows, so the index and the foreign
    # key take no time and block nothing.
    safety_assured do
      change_table :oauth_applications, bulk: true do |t|
        t.boolean :show_in_launcher, default: false, null: false
        t.string :launch_url
        t.string :launcher_icon_url
        t.text :launcher_description
        t.references :access_request_group, foreign_key: { to_table: :groups, on_delete: :nullify }
      end
    end
  end

end
