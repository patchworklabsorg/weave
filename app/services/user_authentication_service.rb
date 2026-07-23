# frozen_string_literal: true

class UserAuthenticationService
  class AuthenticationError < StandardError; end

  def initialize(user)
    @user = user
  end

  # Authenticate user with password
  def authenticate_with_password(password)
    return false unless @user&.authenticate(password)

    @user
  end

  # Create a new session for the user
  def create_session(request:, admin_id: nil, impersonated_by: nil)
    session_params = {
      device_info: extract_device_info(request),
      os_info: extract_os_info(request),
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      timezone: extract_timezone(request),
      impersonated_by_id: impersonated_by&.id
    }

    # Add geolocation if available
    location = geocode_ip(request.remote_ip)
    session_params.merge!(location) if location

    @user.user_sessions.create!(session_params)
  end

  # Check if user can be impersonated
  def can_be_impersonated_by?(admin)
    return false unless admin&.can_impersonate?
    return false if @user == admin # Can't impersonate yourself
    return false if @user.owner? # Can't impersonate owners

    # Admins can impersonate users, superadmins can impersonate admins and users
    case admin.role
    when "owner", "superadmin"
      true
    when "admin"
      @user.user? # Admins can only impersonate regular users
    else
      false
    end
  end

  private

  def extract_device_info(request)
    browser = Browser.new(request.user_agent)
    "#{browser.name} #{browser.version}"
  end

  def extract_os_info(request)
    browser = Browser.new(request.user_agent)
    "#{browser.platform.name} #{browser.platform.version}"
  end

  def extract_timezone(request)
    # Try to extract from headers or default to UTC
    request.headers["X-Timezone"] || "UTC"
  end

  def geocode_ip(ip_address)
    return nil if ip_address.blank?
    return nil if ip_address == "127.0.0.1" || ip_address.start_with?("192.168.")

    result = Geocoder.search(ip_address).first
    return nil unless result

    {
      city: result.city,
      state: result.state,
      country: result.country,
      latitude: result.latitude,
      longitude: result.longitude
    }
  rescue => e
    Rails.logger.error("Failed to geocode IP #{ip_address}: #{e.message}")
    nil
  end

end
