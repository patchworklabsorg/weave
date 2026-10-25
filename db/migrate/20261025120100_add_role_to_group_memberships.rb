# frozen_string_literal: true

# A group manager approves access requests for the group and manages its
# members (see GroupPolicy).
class AddRoleToGroupMemberships < ActiveRecord::Migration[8.1]
  def change
    # A string with a constant default: Postgres 11+ adds it with no table
    # rewrite.
    add_column :group_memberships, :role, :string, default: "member", null: false
  end

end
