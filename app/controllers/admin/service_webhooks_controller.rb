# frozen_string_literal: true

# The webhooks of a service (see docs/WEBHOOKS.md). The page shows the
# delivery log. Only a superadmin sees the signing secret.
class Admin::ServiceWebhooksController < Admin::BaseController
  include RequiresServiceSuperadmin

  DELIVERIES_SHOWN = 50

  before_action :set_service
  before_action :set_webhook, only: [:show, :edit, :update, :destroy, :activate, :deactivate, :test, :rotate_secret]
  before_action :require_service_superadmin, except: [:index, :show]

  # The webhooks are listed on the service page.
  def index
    redirect_to admin_service_path(@service, anchor: "webhooks")
  end

  def show
    @deliveries = @webhook.deliveries.order(created_at: :desc).limit(DELIVERIES_SHOWN)
    @delivery_counts = @webhook.deliveries.group(:status).count
  end

  def new
    @webhook = @service.webhooks.build
  end

  def create
    @webhook = @service.webhooks.build(webhook_params)
    @webhook.created_by = current_user

    if @webhook.save
      redirect_to admin_service_webhook_path(@service, @webhook), notice: "Webhook was created. Give the signing secret to the service, then send a test."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @webhook.update(webhook_params)
      redirect_to admin_service_webhook_path(@service, @webhook), notice: "Webhook was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @webhook.destroy
    redirect_to admin_service_path(@service, anchor: "webhooks"), notice: "Webhook was deleted with its delivery log."
  end

  def activate
    @webhook.activate!
    redirect_to admin_service_webhook_path(@service, @webhook), notice: "Webhook activated. Its failure count is back to 0."
  end

  def deactivate
    @webhook.deactivate!
    redirect_to admin_service_webhook_path(@service, @webhook), notice: "Webhook deactivated. Queued deliveries are cancelled."
  end

  # Sends a signed `ping` event, so the receiver can check its URL and secret.
  def test
    unless @webhook.active? && @service.active?
      return redirect_to admin_service_webhook_path(@service, @webhook), alert: "Activate the webhook and its service before you send a test."
    end

    WebhookDispatcher.ping(@webhook)
    redirect_to admin_service_webhook_path(@service, @webhook), notice: "Test webhook queued. Reload the page to see the result in the delivery log."
  end

  # A new secret signs every attempt from now on, retries too. The receiver
  # must have the new secret before the next delivery.
  def rotate_secret
    @webhook.rotate_secret!
    redirect_to admin_service_webhook_path(@service, @webhook), notice: "Signing secret rotated. Give the new secret to the service now."
  end

  private

  def set_service
    @service = Service.find_by_public_param!(params[:service_id])
  end

  def set_webhook
    @webhook = @service.webhooks.find_by_public_param!(params[:id])
  end

  def webhook_params
    params.require(:service_webhook).permit(:url, :event_type)
  end

end
