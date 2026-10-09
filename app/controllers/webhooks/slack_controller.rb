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

    # Slack interactivity. Handles the code-of-conduct DM (see
    # SlackService#post_code_of_conduct):
    #
    # - "accept_coc" button: accepts at once, and promotes a single-channel
    #   guest to a full member.
    # - "open_coc_form" button: opens the form that asks for a missing name.
    # - Submission of that form: saves the name and accepts.
    #
    # Slack posts the interaction as a form-encoded `payload` field.
    def interactions
      payload = JSON.parse(params[:payload].to_s.presence || "{}")

      if payload["type"] == "view_submission"
        return submit_code_of_conduct_form(payload) if payload.dig("view", "callback_id") == SlackService::CODE_OF_CONDUCT_FORM

        head :ok
        return
      end

      action = (payload["actions"] || []).first || {}

      case action["action_id"]
      when "accept_coc"
        slack_user_id = action["value"].presence || payload.dig("user", "id")
        SlackCodeOfConductAcceptedJob.perform_later(slack_user_id) if slack_user_id.present?

        # Replace the original message so the button can't be used twice.
        already_member = User.find_by(slack_id: slack_user_id)&.slack_member? || false
        render json: { replace_original: true, text: SlackService.code_of_conduct_thanks(already_member:) }
      when "open_coc_form"
        open_code_of_conduct_form(payload)
        head :ok
      else
        head :ok
      end
    rescue JSON::ParserError => e
      Rails.logger.error "[Slack Interactions] Invalid payload: #{e.message}"
      head :bad_request
    end

    private

    # Called while Slack waits for the answer to the click: the trigger_id
    # expires after 3 seconds.
    def open_code_of_conduct_form(payload)
      SlackService.new.open_code_of_conduct_form(
        trigger_id: payload["trigger_id"],
        user: User.find_by(slack_id: payload.dig("user", "id")),
        message: { channel: payload.dig("container", "channel_id"), ts: payload.dig("container", "message_ts") }.compact.presence
      )
    rescue => e
      Rails.logger.error "[Slack Interactions] Could not open CoC form: #{e.message}"
    end

    # The person who submits the form is the one who accepts, so the user
    # comes from the payload's user, never from a value in the form.
    def submit_code_of_conduct_form(payload)
      slack_user_id = payload.dig("user", "id")
      values = payload.dig("view", "state", "values") || {}
      message = JSON.parse(payload.dig("view", "private_metadata").presence || "{}").symbolize_keys.slice(:channel, :ts).presence
      user = User.find_by(slack_id: slack_user_id)

      if user
        result = CodeOfConductAcceptance.call(
          user,
          first_name: values.dig("first_name", "value", "value"),
          last_name: values.dig("last_name", "value", "value"),
          message: message
        )
        unless result.success?
          render json: { response_action: "errors", errors: result.errors.transform_keys(&:to_s) }
          return
        end
      elsif slack_user_id.present?
        SlackCodeOfConductAcceptedJob.perform_later(slack_user_id, **{ message: message }.compact)
      end

      render json: { response_action: "clear" }
    end

    def devise_configured?
      defined?(Devise)
    end

  end
end
