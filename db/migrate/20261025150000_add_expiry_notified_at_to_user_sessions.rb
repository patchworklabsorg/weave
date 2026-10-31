# frozen_string_literal: true

# When Weave sent session.expired for the session (see User::Session). A
# session that runs out of time gets the event from NotifyExpiredSessionsJob,
# which looks the sessions up by expiration_at.
class AddExpiryNotifiedAtToUserSessions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :user_sessions, :expiry_notified_at, :datetime
    add_index :user_sessions, :expiration_at, algorithm: :concurrently
  end

end
