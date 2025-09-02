# frozen_string_literal: true

class AddMoreUserData < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :birthday, :date, null: true
    add_column :users, :phone_number, :string, null: true
  end

end
