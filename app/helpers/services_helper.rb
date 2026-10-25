# frozen_string_literal: true

# Status badges and event names for the service, API key and webhook pages.
module ServicesHelper
  WEBHOOK_EVENT_DESCRIPTIONS = {
    "user.created"         => "A user signs up.",
    "user.updated"         => "The name, email, Slack ID or account state of a user changes.",
    "user.deleted"         => "An account is deleted. Only the ID is sent.",
    "session.created"      => "A user signs in.",
    "session.expired"      => "A session ends: sign-out, revocation or time-out.",
    "group.member_added"   => "A user joins a group, by hand or by the system sync.",
    "group.member_removed" => "A user leaves a group: removal, expiry, group or account deletion.",
    "ping"                 => "A test from the admin panel."
  }.freeze

  SERVICE_STATUS_TONES = { "active" => :success, "inactive" => :neutral, "suspended" => :danger }.freeze
  KEY_STATUS_TONES = { "active" => :success, "deprecated" => :warning, "revoked" => :danger }.freeze
  DELIVERY_STATUS_TONES = { "pending" => :info, "delivered" => :success, "failed" => :danger, "cancelled" => :neutral }.freeze

  def webhook_event_description(event) = WEBHOOK_EVENT_DESCRIPTIONS.fetch(event, event)

  # [label, value] pairs for the event select, with the description.
  def webhook_event_options
    Service::Webhook::EVENT_TYPES.map { |event| ["#{event}: #{webhook_event_description(event)}", event] }
  end

  def service_status_badge(service)
    badge(service.status.humanize, tone: SERVICE_STATUS_TONES.fetch(service.status, :neutral))
  end

  def service_key_status_badge(key)
    return badge("Expired", tone: :danger) if key.expired? && !key.revoked?

    badge(key.status.humanize, tone: KEY_STATUS_TONES.fetch(key.status, :neutral))
  end

  def webhook_status_badge(webhook)
    webhook.active? ? badge("Active", tone: :success) : badge("Inactive", tone: :neutral)
  end

  def webhook_delivery_status_badge(delivery)
    badge(delivery.status.humanize, tone: DELIVERY_STATUS_TONES.fetch(delivery.status, :neutral))
  end

  # The last answer of a delivery: the HTTP status, or the error.
  def webhook_delivery_result(delivery)
    response = delivery.response || {}
    if response["status"]
      "HTTP #{response['status']}"
    elsif response["error"]
      response["error"]
    else
      "Not sent yet"
    end
  end
end
