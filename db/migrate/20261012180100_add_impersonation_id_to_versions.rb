# frozen_string_literal: true

class AddImpersonationIdToVersions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Links each PaperTrail version made while an admin impersonated a user to
  # that impersonation. No foreign key: versions are an append-only audit log
  # and must outlive the rows they point to.
  def change
    add_column :versions, :impersonation_id, :bigint
    add_index :versions, :impersonation_id, algorithm: :concurrently
  end

end
