# frozen_string_literal: true

# Sends a person back to the page that asked them to sign in, instead of the
# dashboard (#117).
#
# authenticate_user! stores the requested path in the session before it sends
# the person to /login. The session carries it through a magic link: the person
# leaves for their email client and comes back in the same browser.
# complete_login takes it out again.
#
# The stored value goes straight into redirect_to, so safe_return_path accepts
# only a local path. Rails sends a value that starts with "//" or a scheme to
# that host as-is, which would make this an open redirect.
module ReturnAfterSignIn
  extend ActiveSupport::Concern

  SESSION_KEY = :return_to

  # The session is a cookie (4 KB in all), so a long query string is dropped
  # rather than stored.
  MAX_LENGTH = 1024

  # Sign-in and sign-out pages. Returning to one of them after sign-in would
  # loop or sign the person out again.
  EXCLUDED_PREFIXES = %w[/login /logout /oauth/login /auth].freeze

  private

  # Only a full-page GET: a form post can't be replayed, and a Turbo Frame or
  # JSON request is not a page the person can land on. A Turbo hover prefetch
  # is not a visit either, and would replace the page the person asked for.
  def store_return_path
    return unless request.get? && request.format.html? && !turbo_frame_request?
    return if request.headers["X-Sec-Purpose"].to_s.include?("prefetch")

    path = safe_return_path(request.fullpath)
    session[SESSION_KEY] = path if path
  end

  def take_return_path
    safe_return_path(session.delete(SESSION_KEY))
  end

  def safe_return_path(value)
    path = value.to_s
    return nil if path.empty? || path.length > MAX_LENGTH
    return nil unless path.start_with?("/")
    # Browsers read a backslash as a slash, so "/\evil.com" is "//evil.com".
    # Control characters (a tab or newline inside "//") are stripped by
    # browsers too.
    return nil if path.start_with?("//") || path.match?(/[\\[:cntrl:]]/)

    uri = URI.parse(path)
    return nil if uri.scheme || uri.host
    return nil if EXCLUDED_PREFIXES.any? { |prefix| uri.path == prefix || uri.path.start_with?("#{prefix}/") }

    path
  rescue URI::InvalidURIError
    nil
  end
end
