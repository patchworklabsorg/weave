# frozen_string_literal: true

module Webhooks
  class SlackController < ApplicationController
    include SlackSignatureVerification

    # Skip default protections - we verify via Slack signature instead
    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user!
    # Both endpoints are unauthenticated apart from Slack's signature, and events
    # create users and change their email addresses (what magic links go to),
    # so neither may skip it.
    before_action :verify_slack_signature, only: %i[events interactions]

    def events
      event_data = JSON.parse(request.raw_post)

      # Handle URL verification challenge (Slack handshake)
      if event_data["type"] == "url_verification"
        render json: { challenge: event_data["challenge"] }
        return
      end

      # Handle event callbacks
      if event_data["type"] == "event_callback"
        event_id = event_data["event_id"]

        # Deduplicate events using Rails cache
        cache_key = "slack_event:#{event_id}"
        if Rails.cache.exist?(cache_key)
          Rails.logger.info "[Slack Webhook] Duplicate event #{event_id}, skipping"
          render json: { status: "ok" }, status: :ok
          return
        end

        # Mark event as seen (24 hour TTL)
        Rails.cache.write(cache_key, true, expires_in: 24.hours)

        # Process event asynchronously
        SlackWebhookEventJob.perform_later(event_data)

        # Respond immediately (Slack requires response within 3 seconds)
        render json: { status: "ok" }, status: :ok
        return
      end

      # Unknown event type
      Rails.logger.warn "[Slack Webhook] Unknown event type: #{event_data['type']}"
      render json: { status: "ok" }, status: :ok
    rescue JSON::ParserError => e
      Rails.logger.error "[Slack Webhook] Invalid JSON: #{e.message}"
      render json: { error: "Invalid JSON" }, status: :bad_request
    rescue => e
      Rails.logger.error "[Slack Webhook] Error processing event: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      # Still return 200 to prevent Slack from retrying
      render json: { status: "ok" }, status: :ok
    end

    # Slack interactivity (Block Kit button clicks). Handles the "I accept the
    # Code of Conduct" button, which promotes a single-channel guest to a full
    # member. Slack posts the interaction as a form-encoded `payload` field.
    def interactions
      payload = JSON.parse(params[:payload].to_s.presence || "{}")
      action = (payload["actions"] || []).first || {}

      if action["action_id"] == "accept_coc"
        slack_user_id = action["value"].presence || payload.dig("user", "id")
        SlackCodeOfConductAcceptedJob.perform_later(slack_user_id) if slack_user_id.present?

        # Replace the original message so the button can't be used twice.
        render json: {
          replace_original: true,
          text: ":white_check_mark: Thanks for accepting the Code of Conduct — you now have full access to the Patchwork Labs Slack. Welcome! :tada:"
        }
        return
      end

      head :ok
    rescue JSON::ParserError => e
      Rails.logger.error "[Slack Interactions] Invalid payload: #{e.message}"
      head :bad_request
    end

    private

    def devise_configured?
      defined?(Devise)
    end

  end
end
