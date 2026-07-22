# frozen_string_literal: true

class AddIsBoardToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :is_board, :boolean, default: false, null: false
  end

end
