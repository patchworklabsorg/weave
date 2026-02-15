# frozen_string_literal: true

module SlackSignatureVerification
  extend ActiveSupport::Concern

  included do
    before_action :verify_slack_signature, only: [:events]
  end

  private

  def verify_slack_signature
    # Get the signing secret from credentials or ENV
    signing_secret = slack_signing_secret

    unless signing_secret.present?
      Rails.logger.error "[Slack Webhook] Missing signing secret"
      render json: { error: "Configuration error" }, status: :internal_server_error
      return
    end

    # Get signature and timestamp from headers
    slack_signature = request.headers['X-Slack-Signature']
    slack_timestamp = request.headers['X-Slack-Request-Timestamp']

    unless slack_signature.present? && slack_timestamp.present?
      Rails.logger.warn "[Slack Webhook] Missing signature headers"
      render json: { error: "Unauthorized" }, status: :unauthorized
      return
    end

    # Prevent replay attacks - reject requests older than 5 minutes
    if Time.current.to_i - slack_timestamp.to_i > 300
      Rails.logger.warn "[Slack Webhook] Timestamp too old: #{slack_timestamp}"
      render json: { error: "Request too old" }, status: :unauthorized
      return
    end

    # Compute expected signature
    # Format: v0=HMAC-SHA256(signing_secret, "v0:timestamp:body")
    sig_basestring = "v0:#{slack_timestamp}:#{request.raw_post}"
    computed_signature = "v0=" + OpenSSL::HMAC.hexdigest(
      OpenSSL::Digest.new('SHA256'),
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
    if Rails.application.credentials.dig(:slack, :signing_secret).present?
      Rails.application.credentials.dig(:slack, :signing_secret)
    else
      ENV['SLACK_SIGNING_SECRET']
    end
  end
end
