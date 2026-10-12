# frozen_string_literal: true

class KeepGuardianConsentsAfterAccountDeletion < ActiveRecord::Migration[8.1]
  def change
    # A consent stays for 1 year after its account is deleted (see
    # PurgeGuardianConsentsJob), so the row must outlive the user row.
    add_column :guardian_consents, :account_deleted_at, :datetime
    change_column_null :guardian_consents, :user_id, true
    remove_foreign_key :guardian_consents, :users, column: :user_id
    add_foreign_key :guardian_consents, :users, column: :user_id, on_delete: :nullify, validate: false
  end

end
