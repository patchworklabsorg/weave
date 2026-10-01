# frozen_string_literal: true

class AddSlackMembershipToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :slack_membership, :string, default: "pending", null: false
  end
end
