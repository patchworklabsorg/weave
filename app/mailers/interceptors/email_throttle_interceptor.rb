# frozen_string_literal: true

module Interceptors
  class EmailThrottleInterceptor
    DAILY_LIMIT = 2000
    WARNING_THRESHOLD = 1900
    ALERT_EMAIL = "jasper@patchworklabs.org"

    def self.delivering_email(message)
      return unless Rails.env.production?

      redis = Redis.new(url: ENV["REDIS_CACHE_URL"], ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE })
      today = Date.current.to_s
      key = "email_count:#{today}"

      # Get current count
      count = redis.get(key).to_i

      # Check if over limit
      if count >= DAILY_LIMIT
        Rails.logger.error("Email throttle limit reached: #{count}/#{DAILY_LIMIT} for #{today}")
        message.perform_deliveries = false
        return
      end

      # Increment counter and set expiry for 2 days
      new_count = redis.incr(key)
      redis.expire(key, 2.days.to_i)

      # Send warning email if approaching limit
      if new_count == WARNING_THRESHOLD && message.to != [ALERT_EMAIL]
        send_warning_email(new_count, today)
      end
    rescue Redis::BaseError => e
      # Log error but don't block email sending if Redis is down
      Rails.logger.error("Email throttle Redis error: #{e.message}")
    end

    def self.send_warning_email(count, date)
      AdminMailer.email_throttle_warning(count, date).deliver_later
    rescue => e
      Rails.logger.error("Failed to send email throttle warning: #{e.message}")
    end

  end
end
