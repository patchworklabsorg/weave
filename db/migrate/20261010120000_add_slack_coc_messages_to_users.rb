# frozen_string_literal: true

class AddSlackCocMessagesToUsers < ActiveRecord::Migration[8.1]
  def change
    # The code-of-conduct DMs sent to a user that still have a live button, as
    # [{ "channel" => ..., "ts" => ... }]. They are all replaced with a
    # thank-you once the user accepts, from Slack or the web.
    add_column :users, :slack_coc_messages, :jsonb, default: [], null: false
  end
end
