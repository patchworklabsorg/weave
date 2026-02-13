# frozen_string_literal: true

class ServiceKeyUsageSerializer
  def initialize(usage)
    @usage = usage
  end

  def as_json
    {
      id: @usage.id,
      request_path: @usage.request_path,
      request_method: @usage.request_method,
      response_code: @usage.response_code,
      duration_ms: @usage.duration_ms,
      ip_address: @usage.ip_address,
      requested_at: @usage.requested_at,
      success: @usage.success?,
      error: @usage.error?
    }
  end

  def to_json(*args)
    as_json.to_json(*args)
  end

  class << self
    def render(usage)
      new(usage).as_json
    end

    def render_collection(usages)
      usages.map { |usage| new(usage).as_json }
    end
  end
end
