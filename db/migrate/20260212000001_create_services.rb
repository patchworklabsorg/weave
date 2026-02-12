# frozen_string_literal: true

class CreateServices < ActiveRecord::Migration[8.0]
  def change
    create_table :services do |t|
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: "active"
      t.references :created_by, foreign_key: { to_table: :users }, null: false

      t.timestamps
    end

    add_index :services, :name, unique: true
    add_index :services, :status
  end
end
