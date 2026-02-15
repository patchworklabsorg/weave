# frozen_string_literal: true

class AddSlackProfileFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    # Pull-only fields (user editable in Slack)
    add_column :users, :slack_pronouns, :string
    add_column :users, :slack_display_name, :string
    add_column :users, :slack_status_text, :string
    add_column :users, :slack_status_emoji, :string
    add_column :users, :slack_phone, :string
    add_column :users, :slack_start_date, :date
    add_column :users, :slack_role_description, :text
    add_column :users, :slack_website, :string
    add_column :users, :slack_github, :string
    add_column :users, :slack_linkedin, :string
    add_column :users, :slack_birthday, :date
    add_column :users, :slack_profile_image_url, :string

    # Push & pull fields (API editable)
    add_column :users, :slack_title, :string
    add_column :users, :slack_city, :string
    add_column :users, :slack_state, :string
    add_column :users, :slack_country, :string
    add_column :users, :slack_manager_id, :string # Slack user ID of manager
    add_column :users, :slack_organization, :string
    add_column :users, :slack_division, :string
    add_column :users, :slack_department, :string
    add_column :users, :slack_cost_center, :string

    # Metadata
    add_column :users, :slack_profile_synced_at, :datetime
  end
end
