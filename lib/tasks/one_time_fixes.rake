# frozen_string_literal: true

namespace :one_time do
  desc "Mark users with managers as contractors"
  task mark_managed_as_contractors: :environment do
    puts "Finding users with managers..."

    users_with_managers = User.where.not(manager_id: nil)
    count = users_with_managers.count

    puts "Found #{count} users with managers"
    puts "Marking them as contractors..."

    users_with_managers.update_all(is_contractor: true)

    puts "✅ Updated #{count} users to is_contractor=true"

    # Show summary
    puts "\nSummary:"
    User.where(is_contractor: true).find_each do |user|
      manager_name = user.manager&.full_name || "None"
      puts "  - #{user.full_name} (#{user.email}) → Manager: #{manager_name}"
    end
  end
end
