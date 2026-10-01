# frozen_string_literal: true

class ApiMetricsService
  class << self
    def record_request(usage_record)
      return unless usage_record

      # Record basic metrics
      increment_counter("api.requests.total", tags: tags_for_usage(usage_record))

      # Record response codes
      increment_counter("api.responses.#{response_category(usage_record.response_code)}",
                        tags: tags_for_usage(usage_record))

      # Record duration
      if usage_record.duration_ms
        record_histogram("api.request.duration", usage_record.duration_ms,
                         tags: tags_for_usage(usage_record))
      end

    rescue => e
      Rails.logger.error("Failed to record API request metrics: #{e.message}")
    end

    def record_endpoint_metrics(path, method, duration_ms, response_code, service_name)
      tags = {
        path: normalize_path(path),
        method: method,
        status: response_code,
        service: service_name || "unknown"
      }

      # Record endpoint-specific metrics
      increment_counter("api.endpoint.requests", tags: tags)
      record_histogram("api.endpoint.duration", duration_ms, tags: tags) if duration_ms

      # Record errors
      if response_code && response_code >= 400
        increment_counter("api.endpoint.errors", tags: tags)
      end

    rescue => e
      Rails.logger.error("Failed to record endpoint metrics: #{e.message}")
    end

    private

    def increment_counter(metric_name, tags: {})
      # In production, this would send to StatsD/Datadog/etc
      # For now, just log it
      Rails.logger.info("Metric: #{metric_name} | Tags: #{tags.inspect}")

      # If you have StatsD configured, uncomment:
      # StatsD.increment(metric_name, tags: tags)
    end

    def record_histogram(metric_name, value, tags: {})
      # In production, this would send to StatsD/Datadog/etc
      # For now, just log it
      Rails.logger.info("Metric: #{metric_name} = #{value} | Tags: #{tags.inspect}")

      # If you have StatsD configured, uncomment:
      # StatsD.histogram(metric_name, value, tags: tags)
    end

    def tags_for_usage(usage_record)
      {
        service_key_id: usage_record.service_key_id,
        path: normalize_path(usage_record.request_path),
        method: usage_record.request_method,
        status: usage_record.response_code
      }
    end

    def normalize_path(path)
      return "unknown" if path.blank?

      # Normalize paths by removing IDs and other variable segments
      # /api/v1/users/123 -> /api/v1/users/:id
      path.gsub(/\/\d+/, "/:id")
          .gsub(/\/[a-f0-9-]{36}/, "/:uuid")  # UUIDs
          .gsub(/\/S?PWL[A-Z0-9]+/, "/:p_id") # Custom p_id format (SPWL on staging)
    end

    def response_category(code)
      return "unknown" unless code

      case code
      when 200..299 then "2xx"
      when 300..399 then "3xx"
      when 400..499 then "4xx"
      when 500..599 then "5xx"
      else "unknown"
      end
    end

  end

end
