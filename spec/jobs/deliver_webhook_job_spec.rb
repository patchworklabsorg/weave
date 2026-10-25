# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeliverWebhookJob do
  include ActiveJob::TestHelper

  let(:webhook) { create(:service_webhook, url: "https://hooks.example.com/weave?a=1") }
  let(:delivery) { WebhookDispatcher.emit("group.member_added", { user: { id: "PWL1" } }).sole }
  let(:http) { instance_spy(Net::HTTP) }
  let(:requests) { [] }

  before do
    webhook
    delivery
    clear_enqueued_jobs
    allow(WebhookUrlGuard).to receive(:check!) { |url| [URI.parse(url), "93.184.216.34"] }
    allow(Net::HTTP).to receive(:new).with("hooks.example.com", 443, nil).and_return(http)
  end

  def answer(code, body = "")
    allow(http).to receive(:request) do |request|
      requests << request
      instance_double(Net::HTTPResponse, code: code.to_s, body: body)
    end
  end

  it "posts the stored body, signed with the webhook secret" do
    answer(200, "ok")
    body = delivery.payload

    travel_to Time.zone.at(1_700_000_000) do
      described_class.perform_now(delivery)
    end

    request = requests.sole
    expect(request.path).to eq("/weave?a=1")
    expect(request.body).to eq(body)
    expect(JSON.parse(body)).to include("type" => "group.member_added", "data" => { "user" => { "id" => "PWL1" } })
    headers = %w[X-Weave-Event X-Weave-Event-Id X-Weave-Delivery X-Weave-Timestamp X-Weave-Signature].map { request[_1] }
    signature = WebhookDispatcher.signature(webhook.secret_token, "1700000000", body)
    expect(headers).to eq(["group.member_added", delivery.event_id, delivery.public_id, "1700000000", signature])
  end

  it "connects over TLS to the address the guard checked" do
    answer(200)
    expect(http).to receive(:ipaddr=).with("93.184.216.34")
    expect(http).to receive(:use_ssl=).with(true)

    described_class.perform_now(delivery)
  end

  it "marks the delivery delivered, clears the body, and resets the webhook failures" do
    webhook.update!(failure_count: 3)
    answer(204)

    described_class.perform_now(delivery)

    delivery.reload
    expect(delivery).to be_delivered
    expect(delivery.payload).to be_nil
    expect(delivery.attempts).to eq(1)
    expect(delivery.response).to include("status" => 204)
    expect(webhook.reload.failure_count).to eq(0)
    expect(webhook.last_triggered_at).to be_present
  end

  it "retries a failed attempt and counts the failure" do
    answer(500, "boom")

    expect { described_class.perform_now(delivery) }.to have_enqueued_job(described_class).with(delivery)

    delivery.reload
    expect(delivery).to be_pending
    expect(delivery.payload).to be_present
    expect(delivery.response).to include("status" => 500, "body" => "boom")
    expect(webhook.reload.failure_count).to eq(1)
  end

  it "fails the delivery after the last attempt" do
    answer(503)

    perform_enqueued_jobs(only: described_class) { described_class.perform_later(delivery) }

    delivery.reload
    expect(requests.size).to eq(DeliverWebhookJob::ATTEMPTS)
    expect(delivery).to be_failed
    expect(delivery.attempts).to eq(DeliverWebhookJob::ATTEMPTS)
    expect(delivery.payload).to be_nil
  end

  it "turns the webhook off after 10 failures in a row and cancels what is left" do
    webhook.update!(failure_count: 9)
    answer(500)

    expect { described_class.perform_now(delivery) }.not_to have_enqueued_job(described_class)

    expect(webhook.reload).to be_inactive
    expect(delivery.reload).to be_cancelled
    expect(delivery.response).to include("status" => 500)
    expect(requests.size).to eq(1)
  end

  it "counts a blocked URL as a failed attempt and sends nothing" do
    allow(WebhookUrlGuard).to receive(:check!).and_raise(WebhookUrlGuard::Blocked, "hooks.example.com resolves to a blocked address")

    expect(Net::HTTP).not_to receive(:new)

    expect { described_class.perform_now(delivery) }.to have_enqueued_job(described_class)

    expect(delivery.reload.response["error"]).to include("blocked address")
    expect(webhook.reload.failure_count).to eq(1)
  end

  it "counts a timeout as a failed attempt" do
    allow(http).to receive(:request).and_raise(Net::ReadTimeout)

    expect { described_class.perform_now(delivery) }.to have_enqueued_job(described_class)

    expect(delivery.reload.response["error"]).to include("Net::ReadTimeout")
  end

  it "does not send a delivery that is already done" do
    answer(200)
    delivery.finish!("delivered")

    described_class.perform_now(delivery)

    expect(requests).to be_empty
  end
end
