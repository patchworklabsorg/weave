# frozen_string_literal: true

class ServiceKeySerializer
  def initialize(key, options = {})
    @key = key
    @options = options
  end

  def as_json
    base_attributes.tap do |json|
      json[:api_key] = @key.api_key if @options[:include_api_key] && @key.api_key.present?
      json[:recent_usage] = usage_attributes if @options[:include_usage]
    end
  end

  def to_json(*args)
    as_json.to_json(*args)
  end

  private

  def base_attributes
    {
      id: @key.id,
      name: @key.name,
      status: @key.status,
      active: @key.active?,
      deprecated: @key.deprecated?,
      revoked: @key.revoked?,
      expired: @key.expired?,
      may_use: @key.may_use?,
      last_used_at: @key.last_used_at,
      expires_at: @key.expires_at,
      created_at: @key.created_at,
      updated_at: @key.updated_at
    }
  end

  def usage_attributes
    @key.usages.recent.limit(10).map { |usage| ServiceKeyUsageSerializer.new(usage).as_json }
  end

  class << self
    def render(key, options = {})
      new(key, options).as_json
    end

    def render_collection(keys, options = {})
      keys.map { |key| new(key, options).as_json }
    end

  end

end
