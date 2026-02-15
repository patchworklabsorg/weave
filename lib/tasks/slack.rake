# frozen_string_literal: true

namespace :slack do
  desc "Clear PWL IDs from Slack profiles (useful for cleaning up dev data)"
  task clear_pwl_ids: :environment do
    puts "🧹 Clearing PWL IDs from Slack profiles..."
    puts "=" * 50

    service = SlackService.new
    cleared_count = 0
    error_count = 0

    User.where.not(slack_id: nil).find_each do |user|
      begin
        # Set the PWL ID field to empty string
        if service.send(:user_token).present?
          client = Slack::Web::Client.new(token: service.send(:user_token))
          client.users_profile_set(
            user: user.slack_id,
            profile: {
              fields: {
                "Xf079Z13308F9" => { value: "" }
              }
            }.to_json
          )
          cleared_count += 1
          puts "  ✅ Cleared PWL ID for #{user.email}"
        else
          puts "  ⚠️  User token not configured, skipping"
          break
        end
      rescue => e
        error_count += 1
        puts "  ❌ Error for #{user.email}: #{e.message}"
      end
    end

    puts ""
    puts "=" * 50
    puts "✅ Cleared #{cleared_count} PWL IDs"
    puts "❌ #{error_count} errors" if error_count > 0
  end

  desc "Sync Slack users to IDP (one direction)"
  task sync_to_idp: :environment do
    puts "🔄 Syncing Slack → IDP..."
    service = SlackService.new
    result = service.sync_slack_users_to_idp
    puts "✅ Synced #{result[:synced]} users, skipped #{result[:skipped]}"
  end

  desc "Sync IDP users to Slack (PWL ID updates only)"
  task sync_to_slack: :environment do
    puts "🔄 Syncing IDP → Slack (PWL IDs)..."
    service = SlackService.new
    result = service.sync_idp_users_to_slack
    puts "✅ Synced #{result[:synced]} PWL IDs, skipped #{result[:skipped]}"
  end

  desc "Run bidirectional sync"
  task sync: :environment do
    puts "🔄 Running bidirectional sync..."
    Rake::Task["slack:sync_to_idp"].invoke
    Rake::Task["slack:sync_to_slack"].invoke
    puts "✅ Bidirectional sync complete!"
  end
end
