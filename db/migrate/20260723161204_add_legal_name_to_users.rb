# frozen_string_literal: true

class AddLegalNameToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.string :legal_first_name
      t.string :legal_last_name
    end
  end

end
