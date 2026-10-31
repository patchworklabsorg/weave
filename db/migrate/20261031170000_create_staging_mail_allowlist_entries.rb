# frozen_string_literal: true

# Staging only: addresses and domains that an owner added in the app, so
# staging can mail them without a credentials change and a deploy (see
# StagingMailAllowlistEntry). Production never reads this table.
class CreateStagingMailAllowlistEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :staging_mail_allowlist_entries do |t|
      # An exact address, or a domain that starts with "@". Stored downcased.
      t.string :entry, null: false
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :staging_mail_allowlist_entries, :entry, unique: true
  end

end
