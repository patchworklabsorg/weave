# frozen_string_literal: true

# Keep raw link tokens out of the request log. See LinkTokenPath.
Rails::Rack::Logger.prepend(LinkTokenPath::RequestLog)

# "Redirected to <url>" lines: the guardian page redirects to itself.
Rails.application.config.filter_redirect << LinkTokenPath::PATTERN
