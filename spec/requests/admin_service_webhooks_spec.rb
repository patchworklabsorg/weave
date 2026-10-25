# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin service webhooks", type: :request do
  let(:superadmin) { create(:user, :superadmin, :verified) }
  let(:admin) { create(:user, :admin, :verified) }
  let(:service) { create(:service, name: "Krater") }
  let(:webhook) { create(:service_webhook, service:, event_type: "user.deleted", url: "https://krater.example.com/hook") }

  context "when signed in as a superadmin" do
    before { sign_in_via_magic_link(superadmin) }

    it "creates a webhook and shows its secret and delivery log" do
      post admin_service_webhooks_path(service), params: { service_webhook: { url: "https://krater.example.com/hook", event_type: "group.member_added" } }

      created = service.webhooks.sole
      expect(response).to redirect_to(admin_service_webhook_path(service, created))
      expect(created.created_by).to eq(superadmin)

      WebhookDispatcher.ping(created)
      get admin_service_webhook_path(service, created)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("group.member_added", created.secret_token, "Delivery log", "ping")
    end

    it "shows the form errors for a bad event" do
      post admin_service_webhooks_path(service), params: { service_webhook: { url: "https://krater.example.com/hook", event_type: "user.exploded" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(service.webhooks).to be_empty
    end

    it "renders the new and edit forms" do
      get new_admin_service_webhook_path(service)
      expect(response.body).to include("group.member_removed")

      get edit_admin_service_webhook_path(service, webhook)
      expect(response).to have_http_status(:ok)
    end

    it "updates the URL" do
      patch admin_service_webhook_path(service, webhook), params: { service_webhook: { url: "https://krater.example.com/new" } }

      expect(webhook.reload.url).to eq("https://krater.example.com/new")
    end

    it "sends a ping from Send test" do
      expect { post test_admin_service_webhook_path(service, webhook) }.to have_enqueued_job(DeliverWebhookJob)

      expect(response).to redirect_to(admin_service_webhook_path(service, webhook))
      expect(webhook.deliveries.sole.event).to eq("ping")
    end

    it "sends no ping to an inactive webhook" do
      webhook.deactivate!

      expect { post test_admin_service_webhook_path(service, webhook) }.not_to have_enqueued_job(DeliverWebhookJob)
      expect(flash[:alert]).to include("Activate the webhook")
    end

    it "rotates the secret" do
      old = webhook.secret_token

      patch rotate_secret_admin_service_webhook_path(service, webhook)

      expect(webhook.reload.secret_token).not_to eq(old)
      expect(webhook.secret_token.length).to eq(64)
    end

    it "deactivates the webhook and cancels its queued deliveries" do
      delivery = WebhookDispatcher.ping(webhook)

      patch deactivate_admin_service_webhook_path(service, webhook)

      expect(webhook.reload).to be_inactive
      expect(delivery.reload).to be_cancelled
      expect(delivery.payload).to be_nil
    end

    it "activates the webhook and resets the failure count" do
      webhook.update!(status: "inactive", failure_count: 10)

      patch activate_admin_service_webhook_path(service, webhook)

      expect(webhook.reload).to be_active
      expect(webhook.failure_count).to eq(0)
    end

    it "deletes the webhook with its delivery log" do
      WebhookDispatcher.ping(webhook)

      delete admin_service_webhook_path(service, webhook)

      expect(response).to redirect_to(admin_service_path(service, anchor: "webhooks"))
      expect(Service::Webhook.exists?(webhook.id)).to be(false)
      expect(WebhookDelivery.count).to eq(0)
    end
  end

  context "when signed in as a plain admin" do
    before { sign_in_via_magic_link(admin) }

    it "shows the webhook and the delivery log, but not the secret or the actions" do
      get admin_service_webhook_path(service, webhook)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Delivery log", "Only a superadmin can see the signing secret")
      expect(response.body).not_to include(webhook.secret_token, "Send test")
    end

    it "can't create, change, test or delete a webhook" do
      post admin_service_webhooks_path(service), params: { service_webhook: { url: "https://evil.example.com/", event_type: "user.created" } }
      expect(response).to redirect_to(admin_service_path(service))
      expect(service.webhooks).to be_empty

      old = webhook.secret_token
      patch rotate_secret_admin_service_webhook_path(service, webhook)
      patch admin_service_webhook_path(service, webhook), params: { service_webhook: { url: "https://evil.example.com/" } }
      post test_admin_service_webhook_path(service, webhook)
      delete admin_service_webhook_path(service, webhook)

      webhook.reload
      expect([webhook.secret_token, webhook.url]).to eq([old, "https://krater.example.com/hook"])
      expect(webhook.deliveries).to be_empty
      expect(flash[:alert]).to include("Only a superadmin")
    end
  end
end
