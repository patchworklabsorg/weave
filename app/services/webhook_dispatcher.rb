# frozen_string_literal: true

# Sends Weave events to the services that registered a webhook for them.
#
# `emit` writes one WebhookDelivery per deliverable webhook, in the caller's
# transaction: if the change rolls back, no delivery is left behind. The
# DeliverWebhookJob for each one is enqueued only after every open
# transaction commits, because the job queue is a different database and
# could otherwise pick up a row it can't see yet.
#
# The body is built here, once, and stored on the delivery, so retries send
# the same bytes. The format and the signature are in docs/WEBHOOKS.md.
module WebhookDispatcher
  class UnknownEvent < ArgumentError; end

  SIGNATURE_VERSION = "sha256"

  class << self
    # Sends `event` with `data` to every active webhook registered for it.
    def emit(event, data)
      raise UnknownEvent, "Unknown webhook event #{event.inspect}" unless Service::Webhook::EVENT_TYPES.include?(event)

      webhooks = Service::Webhook.deliverable.for_event(event).to_a
      return [] if webhooks.empty?

      deliver(webhooks, event, data)
    end

    # Sends a `ping` to one webhook, whatever its event type. The admin
    # "Test" button uses it to check the URL and the secret.
    def ping(webhook)
      data = {
        webhook: { id: webhook.public_id, event_type: webhook.event_type },
        service: { id: webhook.service.public_id, name: webhook.service.name }
      }
      deliver([webhook], "ping", data).first
    end

    # Cancels the queued deliveries about one user (by p_id). An account
    # deletion uses it, so a retry does not send the name and email of a
    # deleted account. A delivery that is in flight can still finish.
    def cancel_pending_for(p_id, events:)
      WebhookDelivery.pending.where(subject_id: p_id, event: events).find_each { |delivery| delivery.finish!("cancelled") }
    end

    # HMAC-SHA256 over "<timestamp>.<body>", hex encoded, with the webhook's
    # secret as the key.
    def signature(secret, timestamp, body)
      "#{SIGNATURE_VERSION}=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{body}")}"
    end

    private

    def deliver(webhooks, event, data)
      event_id = SecureRandom.uuid
      body = { id: event_id, type: event, created_at: Time.current.iso8601(3), data: data }.to_json

      deliveries = webhooks.map do |webhook|
        webhook.deliveries.create!(event: event, event_id: event_id, subject_id: data.dig(:user, :id), url: webhook.url,
                                   payload: body)
      end

      ActiveRecord.after_all_transactions_commit do
        deliveries.each { |delivery| DeliverWebhookJob.perform_later(delivery) }
      end

      deliveries
    end

  end
end
