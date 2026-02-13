# frozen_string_literal: true

class UserSerializer
  def initialize(user, options = {})
    @user = user
    @options = options
  end

  def as_json
    base_attributes.tap do |json|
      json[:addresses] = address_attributes if @options[:include_addresses]
      json[:sessions] = session_attributes if @options[:include_sessions]
    end
  end

  def to_json(*args)
    as_json.to_json(*args)
  end

  private

  def base_attributes
    {
      id: @user.id,
      p_id: @user.p_id,
      email: @user.email,
      first_name: @user.first_name,
      last_name: @user.last_name,
      full_name: @user.full_name,
      initials: @user.initials,
      username: @user.username,
      role: @user.role,
      status: @user.status,
      email_verified: @user.email_verified?,
      created_at: @user.created_at,
      updated_at: @user.updated_at
    }
  end

  def address_attributes
    {
      shipping: @user.shipping_address ? AddressSerializer.new(@user.shipping_address).as_json : nil,
      billing: @user.billing_address ? AddressSerializer.new(@user.billing_address).as_json : nil
    }
  end

  def session_attributes
    @user.user_sessions.recent.limit(5).map do |session|
      SessionSerializer.new(session).as_json
    end
  end

  class << self
    def render(user, options = {})
      new(user, options).as_json
    end

    def render_collection(users, options = {})
      users.map { |user| new(user, options).as_json }
    end
  end
end
