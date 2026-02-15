# frozen_string_literal: true

class AddStaffAndContractorToUsers < ActiveRecord::Migration[8.0]
  def change
    safety_assured do
      change_table :users, bulk: true do |t|
        t.boolean :is_staff, default: false, null: false
        t.boolean :is_contractor, default: false, null: false
      end
    end
  end
end
