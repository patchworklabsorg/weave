# frozen_string_literal: true

namespace :slack do
  desc "Clear PWL IDs from Slack profiles (useful for cleaning up dev data)"
  task clear_pwl_ids: :environment do
    puts "🧹 Clearing PWL IDs from Slack profiles..."
    puts "=" * 50

    service = SlackService.new
    cleared_count = 0
    error_count = 0

    field_id = service.send(:custom_field_id, SlackService::PWL_ID_FIELD)
    abort "Slack workspace has no \"#{SlackService::PWL_ID_FIELD}\" profile field" unless field_id

    User.where.not(slack_id: nil).find_each do |user|
      begin
        # Set the PWL ID field to empty string
        if service.send(:user_token).present?
          client = Slack::Web::Client.new(token: service.send(:user_token))
          client.users_profile_set(
            user: user.slack_id,
            profile: {
              fields: {
                field_id => { value: "" }
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

  # Full members who joined before the code-of-conduct flow never accepted it.
  # These tasks ask them to (see CodeOfConductRequestJob).
  namespace :coc do
    desc "Count full members who have not accepted the code of conduct"
    task status: :environment do
      pending = User.code_of_conduct_pending
      puts "Full members without CoC: #{pending.count}"
      puts "  asked:                  #{pending.where.not(slack_coc_requested_at: nil).count}"
      puts "  not asked yet:          #{pending.where(slack_coc_requested_at: nil).count}"
      puts "  name missing:           #{pending.name_missing.count}"
      puts "All users with a missing name: #{User.name_missing.count}"
    end

    # Shows the message and who gets it. Nothing is sent without SEND=1.
    #
    #   bin/rails slack:coc:request                          # preview
    #   bin/rails slack:coc:request SEND=1                   # ask everyone not asked yet
    #   bin/rails slack:coc:request SEND=1 DEADLINE=2026-11-01
    #   bin/rails slack:coc:request SEND=1 REMIND=1          # ask again, including people already asked
    desc "Ask full members to accept the code of conduct by Slack DM and email (SEND=1 to send)"
    task request: :environment do
      deadline = ENV["DEADLINE"].presence && Date.iso8601(ENV["DEADLINE"])
      reminder = ENV["REMIND"] == "1"
      users = User.code_of_conduct_pending
      users = users.where(slack_coc_requested_at: nil) unless reminder
      users = users.select(&:can_authenticate?)

      sample = users.first || User.new(first_name: "Ada", last_name: "Lovelace")
      puts "Message for #{sample.email.presence || 'a sample member'}:"
      puts "-" * 50
      puts CodeOfConductRequestJob.paragraphs(sample, deadline:).join("\n\n")
      puts "-" * 50
      puts "#{users.size} members to ask#{' (reminder)' if reminder}."

      unless ENV["SEND"] == "1"
        puts "Preview only. Run again with SEND=1 to send."
        next
      end

      # Space the jobs out to stay under Slack's chat.postMessage rate limit.
      users.each_with_index do |user, index|
        CodeOfConductRequestJob.set(wait: (index * 2).seconds).perform_later(user.id, deadline: deadline, reminder: reminder)
      end
      puts "Enqueued #{users.size} requests."
    end
  end
end
