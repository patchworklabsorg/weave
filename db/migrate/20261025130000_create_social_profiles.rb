# frozen_string_literal: true

# Accounts on other sites that a member proved are theirs (see SocialProfile).
# Only the public handle and the site's stable account id are kept, never an
# access token.
class CreateSocialProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :social_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :provider, null: false
      # The site's account id. It stays the same when the handle changes.
      t.string :uid, null: false
      t.string :username, null: false
      t.timestamps
    end

    # One account of each site per member, and one member per account.
    add_index :social_profiles, [:user_id, :provider], unique: true
    add_index :social_profiles, [:provider, :uid], unique: true
  end

end
