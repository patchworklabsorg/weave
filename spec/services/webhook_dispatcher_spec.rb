# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookDispatcher do
  let(:service) { create(:service) }

  describe ".emit" do
    it "writes one delivery per active webhook for the event and enqueues each one" do
      first = create(:service_webhook, service:, event_type: "user.created")
      second = create(:service_webhook, event_type: "user.created")
      create(:service_webhook, service:, event_type: "user.created", status: "inactive")
      create(:service_webhook, service:, event_type: "user.deleted")
      create(:service_webhook, service: create(:service, status: "suspended"), event_type: "user.created")

      deliveries = nil
      expect { deliveries = described_class.emit("user.created", { user: { id: "PWL1" } }) }
        .to have_enqueued_job(DeliverWebhookJob).exactly(2).times

      expect(deliveries.map(&:webhook)).to contain_exactly(first, second)
      expect(deliveries.map(&:event_id).uniq.size).to eq(1)
      expect(deliveries).to all(be_pending)
    end

    it "builds the envelope once and stores it as the body" do
      create(:service_webhook, service:, event_type: "user.created")

      delivery = described_class.emit("user.created", { user: { id: "PWL1" } }).sole
      body = JSON.parse(delivery.payload)

      expect(body).to include("id" => delivery.event_id, "type" => "user.created", "data" => { "user" => { "id" => "PWL1" } })
      expect(Time.iso8601(body["created_at"])).to be_within(5.seconds).of(Time.current)
    end

    it "does nothing when no webhook listens for the event" do
      expect { described_class.emit("user.created", {}) }.not_to have_enqueued_job
      expect(WebhookDelivery.count).to eq(0)
    end

    it "rejects an event that is not in EVENT_TYPES" do
      expect { described_class.emit("user.exploded", {}) }.to raise_error(WebhookDispatcher::UnknownEvent)
    end

    it "leaves no delivery behind when the change rolls back" do
      create(:service_webhook, service:, event_type: "user.created")

      expect do
        ActiveRecord::Base.transaction do
          described_class.emit("user.created", {})
          raise ActiveRecord::Rollback
        end
      end.not_to have_enqueued_job

      expect(WebhookDelivery.count).to eq(0)
    end
  end

  describe ".ping" do
    it "sends a ping to the one webhook, whatever its event type" do
      webhook = create(:service_webhook, service:, event_type: "user.deleted")

      delivery = nil
      expect { delivery = described_class.ping(webhook) }.to have_enqueued_job(DeliverWebhookJob)

      expect(delivery.event).to eq("ping")
      expect(JSON.parse(delivery.payload)["data"]).to eq(
        "webhook" => { "id" => webhook.public_id, "event_type" => "user.deleted" },
        "service" => { "id" => service.public_id, "name" => service.name }
      )
    end
  end

  describe ".signature" do
    it "is the hex HMAC-SHA256 of the timestamp, a dot and the body" do
      expected = OpenSSL::HMAC.hexdigest("SHA256", "secret", "1700000000.{}")

      expect(described_class.signature("secret", "1700000000", "{}")).to eq("sha256=#{expected}")
    end
  end
end
