# frozen_string_literal: true

class AddSlackCocRequestedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    # When Weave last asked a member who joined before the code-of-conduct
    # flow to accept it (see CodeOfConductRequestJob).
    add_column :users, :slack_coc_requested_at, :datetime
  end
end
