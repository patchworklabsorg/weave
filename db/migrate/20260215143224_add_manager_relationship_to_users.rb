# frozen_string_literal: true

class AddManagerRelationshipToUsers < ActiveRecord::Migration[8.0]
  def change
    safety_assured do
      add_reference :users, :manager, foreign_key: { to_table: :users }, null: true
    end
  end
end
