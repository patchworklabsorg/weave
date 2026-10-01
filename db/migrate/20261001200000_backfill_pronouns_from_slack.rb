# frozen_string_literal: true

# Pronouns are now one field synced with Slack. Copies the old pull-only Slack
# value into it for everyone who has not set pronouns in Weave.
class BackfillPronounsFromSlack < ActiveRecord::Migration[8.1]
  def up
    safety_assured do
      execute <<~SQL.squish
        UPDATE users
        SET pronouns = slack_pronouns
        WHERE pronouns IS NULL
          AND slack_pronouns IS NOT NULL
          AND slack_pronouns <> ''
      SQL
    end
  end

  def down
    # Nothing to undo: pronouns set this way are indistinguishable from edits.
  end
end
