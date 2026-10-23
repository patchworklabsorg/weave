# frozen_string_literal: true

class AddIdentityTeamToUsers < ActiveRecord::Migration[8.1]
  def change
    # The identity team runs identity verification (see Verification). Key
    # holders approve break-glass access to stored ID images. The lead gets
    # every break-glass notice and resolves escalations.
    add_column :users, :identity_team, :boolean, default: false, null: false
    add_column :users, :identity_key_holder, :boolean, default: false, null: false
    add_column :users, :identity_lead, :boolean, default: false, null: false
  end

end
