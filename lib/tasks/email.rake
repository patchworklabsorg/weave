# frozen_string_literal: true

namespace :email do
  desc "Send a test email to verify SMTP configuration"
  task :test, [:recipient] => :environment do |_t, args|
    recipient = args[:recipient] || "jasper@patchworklabs.org"

    puts "Sending test email to #{recipient}..."

    # Temporarily override delivery method for testing
    original_delivery_method = ActionMailer::Base.delivery_method
    original_smtp_settings = ActionMailer::Base.smtp_settings

    begin
      # Configure SMTP for test (even in development)
      if Rails.env.development?
        puts "⚠️  Development mode detected - temporarily enabling SMTP..."

        # Load credentials
        smtp_user = ENV["SMTP_USER_NAME"]
        smtp_pass = ENV["SMTP_PASSWORD"]

        # Try to get from credentials if env vars not set
        if smtp_user.nil? || smtp_pass.nil?
          begin
            creds = Rails.application.credentials
            smtp_user ||= creds.smtp&.user_name
            smtp_pass ||= creds.smtp&.password
          rescue StandardError => e
            puts "⚠️  Could not load credentials: #{e.message}"
          end
        end

        if smtp_user.nil? || smtp_pass.nil?
          raise ArgumentError, "SMTP credentials not found. Set SMTP_USER_NAME and SMTP_PASSWORD env vars or configure in credentials."
        end

        puts "   Using SMTP user: #{smtp_user}"

        ActionMailer::Base.delivery_method = :smtp
        ActionMailer::Base.smtp_settings = {
          address: "smtp.gmail.com",
          port: 587,
          authentication: :plain,
          enable_starttls_auto: true,
          user_name: smtp_user,
          password: smtp_pass
        }
      end

      TestMailer.test_email(recipient).deliver_now
      puts "✅ Test email sent successfully!"
      puts "Check your inbox at #{recipient}"
    rescue StandardError => e
      puts "❌ Failed to send test email:"
      puts "   #{e.class}: #{e.message}"
      puts "\nMake sure you've configured your SMTP credentials either:"
      puts "   1. In Rails credentials: mise exec -- rails credentials:edit"
      puts "   2. Or via environment variables: SMTP_USER_NAME and SMTP_PASSWORD"
      exit 1
    ensure
      # Restore original settings
      if Rails.env.development?
        ActionMailer::Base.delivery_method = original_delivery_method
        ActionMailer::Base.smtp_settings = original_smtp_settings
      end
    end
  end
end
