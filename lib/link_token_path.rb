# frozen_string_literal: true

# The routes that carry a raw link token as a path segment (magic link,
# guardian consent, email confirmation). Rails filters parameters and query
# strings, but not the path, so each place that writes a request path to a
# log or a table must pass it through `redact`.
#
# spec/lib/link_token_path_spec.rb fails when a route with a `:token`
# segment is missing from PREFIXES.
module LinkTokenPath
  PREFIXES = %w[guardian auth/magic_link confirm_email emails/confirm].freeze
  FILTERED = "[FILTERED]"

  # Matches a path or a full URL, so it also serves `config.filter_redirect`.
  PATTERN = /\A((?:https?:\/\/[^\/]+)?\/(?:#{Regexp.union(PREFIXES).source})\/)[^\/?#]+/

  def self.redact(path_or_url)
    path_or_url.to_s.sub(PATTERN) { "#{Regexp.last_match(1)}#{FILTERED}" }
  end

  # Rails::Rack::Logger writes `Started GET "<path>"` for every request.
  module RequestLog
    private

    def started_request_message(request)
      path = request.filtered_path
      super.sub(path) { LinkTokenPath.redact(path) }
    end
  end
end
