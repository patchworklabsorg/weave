# frozen_string_literal: true

class AddSlackInvitedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    # Slack onboarding lifecycle: invited as a single-channel guest, then
    # accepted the code of conduct (which promotes them to a full member).
    add_column :users, :slack_invited_at, :datetime
    add_column :users, :slack_coc_accepted_at, :datetime
  end
end
