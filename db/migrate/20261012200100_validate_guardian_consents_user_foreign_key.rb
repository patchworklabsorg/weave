# frozen_string_literal: true

class ValidateGuardianConsentsUserForeignKey < ActiveRecord::Migration[8.1]
  def change
    validate_foreign_key :guardian_consents, :users, column: :user_id
  end

end
