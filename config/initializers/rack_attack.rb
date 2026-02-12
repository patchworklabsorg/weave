# frozen_string_literal: true

# Rack::Attack configuration for rate limiting and blocking malicious requests
# See https://github.com/rack/rack-attack for more information

class Rack::Attack
  ### Configure Cache ###

  # Use Rails cache for Rack::Attack throttle data
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  ### Throttle (Rate Limiting) Rules ###

  # Throttle login attempts by email address
  # Limit to 5 requests per 20 seconds per email
  throttle("logins/email", limit: 5, period: 20.seconds) do |req|
    if req.path == "/login" && req.post?
      # Return the email as the discriminator
      req.params.dig("user", "email")&.downcase&.presence
    end
  end

  # Throttle magic link requests by email
  # Limit to 3 magic link requests per 5 minutes per email
  throttle("magic_links/email", limit: 3, period: 5.minutes) do |req|
    if (req.path == "/login" || req.path == "/auth/send_magic_link") && req.post?
      req.params.dig("user", "email")&.downcase&.presence
    end
  end

  # Throttle login attempts by IP address
  # Limit to 10 requests per minute per IP for any login endpoint
  throttle("logins/ip", limit: 10, period: 1.minute) do |req|
    if req.path == "/login" && req.post?
      req.ip
    end
  end

  # Throttle signup attempts by IP
  # Limit to 5 signups per hour per IP
  throttle("signups/ip", limit: 5, period: 1.hour) do |req|
    if req.path == "/signup" && req.post?
      req.ip
    end
  end

  # Throttle API requests
  # Limit to 100 requests per minute per IP for API endpoints
  throttle("api/ip", limit: 100, period: 1.minute) do |req|
    if req.path.start_with?("/api/")
      req.ip
    end
  end

  # Throttle OAuth authorization requests
  # Limit to 20 requests per minute per IP
  throttle("oauth/ip", limit: 20, period: 1.minute) do |req|
    if req.path.start_with?("/oauth/")
      req.ip
    end
  end

  ### Custom Response ###

  # Customize the response for throttled requests
  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"]
    now = match_data[:epoch_time]

    headers = {
      "Content-Type" => "application/json",
      "RateLimit-Limit" => match_data[:limit].to_s,
      "RateLimit-Remaining" => "0",
      "RateLimit-Reset" => (now + (match_data[:period] - (now % match_data[:period]))).to_s
    }

    body = {
      error: "Rate limit exceeded. Please try again later.",
      retry_after: match_data[:period]
    }.to_json

    [429, headers, [body]]
  end

  ### Logging ###

  # Log blocked and throttled requests in production
  ActiveSupport::Notifications.subscribe("rack.attack") do |name, start, finish, request_id, payload|
    req = payload[:request]
    if [:throttle].include?(req.env["rack.attack.match_type"])
      Rails.logger.warn "Rack::Attack THROTTLED: #{req.env['rack.attack.matched']} - IP: #{req.ip} - Path: #{req.path}"
    end
  end
end
