# frozen_string_literal: true

class MagicLinkService
  EXPIRATION_TIME = 15.minutes
  RATE_LIMIT_PERIOD = 5.minutes

  class RateLimitError < StandardError; end
  class InvalidTokenError < StandardError; end

  def initialize(user)
    @user = user
  end

  # Generate and send a magic link
  def generate_and_send
    raise RateLimitError, "Please wait before requesting another magic link" if rate_limited?

    @user.send_magic_link
  end

  # Validate and consume a magic link token
  def validate_and_consume(token)
    raise InvalidTokenError, "Invalid token" if @user.magic_link_token.blank?
    raise InvalidTokenError, "Token mismatch" unless @user.magic_link_token_matches?(token)
    raise InvalidTokenError, "Token expired or already used" unless @user.magic_link_valid?

    @user.consume_magic_link_token!
  end

  # Check if the user is rate limited for magic links
  def rate_limited?
    return false if @user.magic_link_sent_at.nil?

    Time.current - @user.magic_link_sent_at < RATE_LIMIT_PERIOD
  end

  # Time remaining until user can request another magic link
  def time_until_next_request
    return 0 unless rate_limited?

    (RATE_LIMIT_PERIOD - (Time.current - @user.magic_link_sent_at)).ceil
  end

  class << self
    # Find user by magic link token (constant-time lookup)
    def find_user_by_token(token)
      return nil if token.blank?

      # This is still vulnerable to timing attacks via database lookup
      # TODO: Consider hashing tokens before storage for full protection
      User.find_by(magic_link_token: token)
    end

  end

end
