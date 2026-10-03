# frozen_string_literal: true

class AddAccessPolicyToOauthApplications < ActiveRecord::Migration[8.1]
  def change
    # "everyone" keeps every existing app open to every user who can sign in.
    add_column :oauth_applications, :access_policy, :string, default: "everyone", null: false

    create_table :application_access_grants do |t|
      t.references :application, null: false, index: false,
                                 foreign_key: { to_table: :oauth_applications, on_delete: :cascade }
      t.references :grantee, null: false, polymorphic: true
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }

      t.timestamps
    end

    add_index :application_access_grants, [:application_id, :grantee_type, :grantee_id], unique: true,
                                                                                         name: "index_application_access_grants_uniqueness"
  end
end
