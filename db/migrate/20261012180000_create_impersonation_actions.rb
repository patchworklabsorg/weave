# frozen_string_literal: true

class CreateImpersonationActions < ActiveRecord::Migration[8.1]
  def change
    # One row per request an admin made while impersonating. The rows belong to
    # the impersonation and go with it.
    create_table :impersonation_actions do |t|
      t.references :impersonation, null: false, foreign_key: { on_delete: :cascade }
      t.string :http_method, null: false
      t.string :path, null: false
      t.string :controller_action
      t.integer :status
      t.jsonb :params, default: {}, null: false
      t.datetime :created_at, null: false
    end
  end

end
