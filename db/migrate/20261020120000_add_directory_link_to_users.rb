# frozen_string_literal: true

# Set when Weave links the user to their Active Directory account (employeeID
# equals p_id). From then on AD holds the only password for the user.
# directory_object_guid pins the AD object, so a second object that later
# gets the same employeeID can't take the account over. See
# docs/ACTIVE_DIRECTORY.md.
class AddDirectoryLinkToUsers < ActiveRecord::Migration[8.1]
  def change
    # Two nullable columns with no default: no table rewrite, no backfill.
    safety_assured do
      change_table :users, bulk: true do |t|
        t.datetime :directory_linked_at
        t.string :directory_object_guid
      end
    end
  end

end
