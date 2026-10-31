# frozen_string_literal: true

namespace :one_time do
  desc "Mark users with managers as contractors"
  task mark_managed_as_contractors: :environment do
    puts "Finding users with managers..."

    users_with_managers = User.where.not(manager_id: nil)
    count = users_with_managers.count

    puts "Found #{count} users with managers"
    puts "Marking them as contractors..."

    users_with_managers.find_each do |user|
      RoleGrants.grant!(user, "contractor", reason: "one_time:mark_managed_as_contractors")
    end

    puts "✅ Gave #{count} users the contractor role"

    # Show summary
    puts "\nSummary:"
    User.contractors.includes(:manager).find_each do |user|
      manager_name = user.manager&.full_name || "None"
      puts "  - #{user.full_name} (#{user.email}) → Manager: #{manager_name}"
    end
  end
end

namespace :one_time do
  # Until 2026-10-30, InviteToSlackJob held back members under 18 until a
  # guardian consented. The Slack no longer needs consent, but nothing runs the
  # job again for the members it held back. Lists them; DRY_RUN=0 invites them.
  desc "Send the Slack invite to members under 18 who waited for guardian consent"
  task invite_minors_held_for_consent: :environment do
    dry_run = ENV.fetch("DRY_RUN", "1") != "0"
    users = User.where.not(email_confirmed_at: nil).where(slack_invited_at: nil, slack_id: nil)
                .select { |user| user.minor? && !user.under_minimum_age? && user.slack_required? }

    users.each_with_index do |user, index|
      puts "#{user.p_id} #{user.full_name}"
      # Spaced out: Slack rate-limits its admin API for the whole workspace.
      InviteToSlackJob.set(wait: index * 2.seconds).perform_later(user.id) unless dry_run
    end
    puts dry_run ? "#{users.size} members. Run with DRY_RUN=0 to invite them." : "Queued #{users.size} invites."
  end
end
