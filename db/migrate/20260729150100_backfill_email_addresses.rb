# frozen_string_literal: true

class BackfillEmailAddresses < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      execute <<~SQL.squish
        INSERT INTO email_addresses (user_id, email, is_primary, confirmed_at, confirmation_sent_at, created_at, updated_at)
        SELECT id, email, TRUE, email_confirmed_at, confirmation_sent_at, NOW(), NOW()
        FROM users
        ON CONFLICT (email) DO NOTHING
      SQL
    end
  end

  def down
    safety_assured do
      execute "DELETE FROM email_addresses"
    end
  end
end
