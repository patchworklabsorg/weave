# frozen_string_literal: true

# A member asks for access to a restricted app (see AccessRequest).
class CreateAccessRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :access_requests do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :application, null: false, foreign_key: { to_table: :oauth_applications, on_delete: :cascade }
      t.references :group, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.text :reason, null: false
      t.string :status, null: false, default: "pending"
      t.references :decided_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :decided_at

      t.timestamps
    end

    add_index :access_requests, [:user_id, :created_at]
    # One open request per member and app.
    add_index :access_requests, [:user_id, :application_id], unique: true, where: "status = 'pending'",
                                                             name: "index_access_requests_one_pending"
    add_index :access_requests, [:group_id, :status]
  end

end
