# frozen_string_literal: true

class AddLegalNameToUsers < ActiveRecord::Migration[8.1]
  # db/schema.rb on main already listed these columns before this migration
  # existed, so some databases may have them.
  def change
    add_column :users, :legal_first_name, :string, if_not_exists: true
    add_column :users, :legal_last_name, :string, if_not_exists: true
  end

end
