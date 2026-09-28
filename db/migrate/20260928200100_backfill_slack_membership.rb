# frozen_string_literal: true

# Best guess from local data. The Slack sync (every 6 hours) then corrects it
# from what Slack reports for each account.
#
# Full members: everyone in the workspace whom Weave did not invite as a guest
# (imported by the member sync, which skips guests), plus guests who accepted
# the code of conduct.
class BackfillSlackMembership < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      execute <<~SQL.squish
        UPDATE users
        SET slack_membership = 'member'
        WHERE slack_id IS NOT NULL
          AND (slack_coc_accepted_at IS NOT NULL OR slack_invited_at IS NULL)
      SQL
    end
  end

  def down
    safety_assured do
      execute "UPDATE users SET slack_membership = 'pending'"
    end
  end
end
