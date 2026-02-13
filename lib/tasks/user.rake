# frozen_string_literal: true

namespace :user do
  desc "Create an owner user - Usage: rails user:create_owner EMAIL='your@email.com' FIRST_NAME='Your' LAST_NAME='Name' PASSWORD='YourSecurePassword123!'"
  task create_owner: :environment do
    email = ENV["EMAIL"] || "jasper@patchworklabs.org"
    first_name = ENV["FIRST_NAME"] || "Jasper"
    last_name = ENV["LAST_NAME"] || "Mayone"
    password = ENV["PASSWORD"]

    if password.blank?
      puts "❌ Error: PASSWORD environment variable is required"
      puts "\nUsage:"
      puts "  rails user:create_owner EMAIL='your@email.com' FIRST_NAME='Your' LAST_NAME='Name' PASSWORD='YourSecurePassword123!'"
      exit 1
    end

    puts "Creating owner user..."
    puts "  Email: #{email}"
    puts "  Name: #{first_name} #{last_name}"
    puts "  Role: owner"

    begin
      user = User.create!(
        email: email,
        first_name: first_name,
        last_name: last_name,
        password: password,
        password_confirmation: password,
        role: :owner,
        status: :active
      )

      puts "\n✅ Owner user created successfully!"
      puts "   User ID: #{user.p_id}"
      puts "   Email: #{user.email}"
      puts "   Role: #{user.role}"
      puts "\nYou can now login at: http://localhost:3000"
    rescue ActiveRecord::RecordInvalid => e
      puts "\n❌ Failed to create user:"
      e.record.errors.full_messages.each do |message|
        puts "   - #{message}"
      end
      exit 1
    end
  end
end
