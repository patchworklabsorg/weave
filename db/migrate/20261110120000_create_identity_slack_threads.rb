# frozen_string_literal: true

# One Slack thread per member in the identity team's channel (see
# IdentitySlackThread). The channel is part of the key, so a new channel
# starts new threads.
class CreateIdentitySlackThreads < ActiveRecord::Migration[8.1]
  def change
    create_table :identity_slack_threads do |t|
      t.references :user, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :channel, null: false
      # The ts of the parent message. Empty until the first post succeeds.
      t.string :ts
      t.timestamps
    end
    add_index :identity_slack_threads, [:user_id, :channel], unique: true
  end

end
