# frozen_string_literal: true

# Magic links live in user_magic_links as of 20260729120000. These columns held
# the single-token-per-user scheme that replaced: one live link at a time, so a
# resend killed the previous email, and the token itself sat here in plaintext.
#
# Nothing reads or writes them anymore — the last references went with
# User#send_magic_link and MagicLinkService.
class DropLegacyMagicLinkColumnsFromUsers < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      remove_column :users, :magic_link_token
      remove_column :users, :magic_link_expires_at
      remove_column :users, :magic_link_sent_at
      remove_column :users, :magic_link_used_at
    end
  end

  # Restores the shape but not the data. Links issued under the old scheme are
  # long expired by the time any rollback happens — they only ever lived 15
  # minutes — so there is nothing worth carrying back.
  def down
    add_column :users, :magic_link_token, :string
    add_column :users, :magic_link_expires_at, :datetime
    add_column :users, :magic_link_sent_at, :datetime
    add_column :users, :magic_link_used_at, :datetime

    add_index :users, :magic_link_token, unique: true
  end
end
