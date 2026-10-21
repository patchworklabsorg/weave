# frozen_string_literal: true

# Set when Weave finds the user's Active Directory account (employeeID equals
# p_id). From then on AD holds the only password for the user. See
# docs/ACTIVE_DIRECTORY.md.
class AddDirectoryLinkToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :directory_linked_at, :datetime
  end

end
