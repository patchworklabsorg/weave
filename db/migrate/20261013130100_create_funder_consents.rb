# frozen_string_literal: true

class CreateFunderConsents < ActiveRecord::Migration[8.1]
  def change
    # A member's consent to be counted in one funder's report (see
    # FunderConsent). Only funders with requires_member_consent use it. The
    # rows go with the account at deletion.
    create_table :funder_consents do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :funder, null: false
      t.datetime :given_at, null: false
      t.datetime :withdrawn_at
      t.timestamps
    end
    add_index :funder_consents, [:user_id, :funder], unique: true, where: "withdrawn_at IS NULL",
                                                     name: "index_funder_consents_on_user_and_funder_live"
    add_index :funder_consents, :funder
  end
end
