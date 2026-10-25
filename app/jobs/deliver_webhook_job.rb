# frozen_string_literal: true

require "net/http"

# POSTs one WebhookDelivery to its webhook (see WebhookDispatcher).
#
# A 2xx answer is a success. Any other answer, a timeout or a blocked URL
# (WebhookUrlGuard) is a failed attempt: it counts against the webhook, which
# Service::Webhook#record_failure! turns off after 10 failures in a row, and
# the job tries again with a growing wait. After ATTEMPTS the delivery is
# failed. Redirects are not followed, so a receiver can't send Weave on to a
# private address.
#
# Each attempt signs the body again with a new timestamp. The event id stays
# the same, so the receiver can drop a delivery it already handled.
class DeliverWebhookJob < ApplicationJob
  class AttemptFailed < StandardError; end

  ATTEMPTS = 8
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10
  USER_AGENT = "Weave-Webhooks/1.0"

  queue_as :default

  # Deleting a webhook deletes its deliveries, queued ones too.
  discard_on ActiveJob::DeserializationError

  retry_on AttemptFailed, wait: :polynomially_longer, attempts: ATTEMPTS do |job, _error|
    delivery = job.arguments.first.reload
    delivery.finish!("failed") if delivery.pending?
  end

  def perform(delivery)
    return unless delivery.pending?

    # A fresh row: the failure count decides when the webhook turns off.
    webhook = delivery.webhook.reload
    return delivery.finish!("cancelled") unless webhook.active? && webhook.service.active?

    response = attempt(delivery, webhook)
    if response[:status].to_i.between?(200, 299)
      delivery.finish!("delivered", delivered_at: Time.current)
      webhook.record_trigger!
      webhook.reset_failures!
    else
      webhook.record_failure!
      # The 10th failure in a row turns the webhook off and cancels this
      # delivery with the others: no retry.
      return unless webhook.active?

      raise AttemptFailed, "Webhook #{webhook.public_id} attempt #{delivery.attempts} failed: #{response[:error] || response[:status]}"
    end
  end

  private

  def attempt(delivery, webhook)
    response = begin
      post(webhook, delivery)
    rescue WebhookUrlGuard::Blocked, SocketError, SystemCallError, IOError, Timeout::Error,
           OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError => e
      { error: "#{e.class}: #{e.message}".truncate(500) }
    end

    delivery.update!(url: webhook.url, attempts: delivery.attempts + 1, last_attempt_at: Time.current,
                     response: response)
    response
  end

  def post(webhook, delivery)
    uri, address = WebhookUrlGuard.check!(webhook.url)
    timestamp = Time.current.to_i.to_s

    request = Net::HTTP::Post.new(uri.request_uri)
    request["Content-Type"] = "application/json"
    request["User-Agent"] = USER_AGENT
    request["X-Weave-Event"] = delivery.event
    request["X-Weave-Event-Id"] = delivery.event_id
    request["X-Weave-Delivery"] = delivery.public_id
    request["X-Weave-Timestamp"] = timestamp
    request["X-Weave-Signature"] = WebhookDispatcher.signature(webhook.secret_token, timestamp, delivery.payload)
    request.body = delivery.payload

    # No proxy from the environment: the connection must go to the address
    # the guard checked, not to a new DNS answer. TLS still checks the
    # certificate against the host name.
    http = Net::HTTP.new(uri.hostname, uri.port, nil)
    http.ipaddr = address
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    http.write_timeout = READ_TIMEOUT

    result = http.request(request)
    { status: result.code.to_i, body: result.body.to_s.dup.force_encoding(Encoding::UTF_8).scrub.truncate(1000) }
  end

end
