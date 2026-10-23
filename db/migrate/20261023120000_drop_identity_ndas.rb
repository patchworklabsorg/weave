# frozen_string_literal: true

# NDAs for the identity team are signed with Adobe Acrobat Sign, outside
# Weave. Weave does not record them, and no precondition checks them.
class DropIdentityNdas < ActiveRecord::Migration[8.1]
  def up
    safety_assured { drop_table :identity_ndas }
  end

  def down
    create_table :identity_ndas do |t|
      t.references :user, foreign_key: { on_delete: :nullify }
      t.date :signed_on, null: false
      t.string :nda_version, null: false
      t.string :signature_reference, null: false
      t.references :recorded_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :created_at, null: false
    end
  end

end
