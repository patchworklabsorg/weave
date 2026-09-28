# frozen_string_literal: true

module SlackSignatureVerification
  extend ActiveSupport::Concern

  # No `included` before_action here on purpose: including controllers declare
  # which actions to verify. Rails keeps only the last before_action registered
  # for a given method, so a default here was silently replaced (and events
  # left unverified) the moment a controller added its own.

  private

  def verify_slack_signature
    # Get the signing secret from credentials or ENV
    signing_secret = slack_signing_secret

    if signing_secret.blank?
      Rails.logger.error "[Slack Webhook] Missing signing secret"
      render json: { error: "Configuration error" }, status: :internal_server_error
      return
    end

    # Get signature and timestamp from headers
    slack_signature = request.headers["X-Slack-Signature"]
    slack_timestamp = request.headers["X-Slack-Request-Timestamp"]

    unless slack_signature.present? && slack_timestamp.present?
      Rails.logger.warn "[Slack Webhook] Missing signature headers"
      render json: { error: "Unauthorized" }, status: :unauthorized
      return
    end

    # Prevent replay attacks - reject requests older than 5 minutes
    if (Time.current.to_i - slack_timestamp.to_i).abs > 300
      Rails.logger.warn "[Slack Webhook] Timestamp too old: #{slack_timestamp}"
      render json: { error: "Request too old" }, status: :unauthorized
      return
    end

    # Compute expected signature
    # Format: v0=HMAC-SHA256(signing_secret, "v0:timestamp:body")
    sig_basestring = "v0:#{slack_timestamp}:#{request.raw_post}"
    computed_signature = "v0=" + OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new("SHA256"),
      signing_secret,
      sig_basestring
    )

    # Use constant-time comparison to prevent timing attacks
    unless ActiveSupport::SecurityUtils.secure_compare(computed_signature, slack_signature)
      Rails.logger.warn "[Slack Webhook] Signature verification failed"
      render json: { error: "Invalid signature" }, status: :unauthorized
      return
    end

    # Signature is valid
    true
  end

  def slack_signing_secret
    # Try Rails credentials first, then ENV
    Rails.application.credentials.dig(:slack, :signing_secret).presence || ENV["SLACK_SIGNING_SECRET"]
  end
end
