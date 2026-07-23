# frozen_string_literal: true

class Admin::ServiceWebhooksController < Admin::BaseController
  before_action :set_service
  before_action :set_webhook, only: [:show, :edit, :update, :destroy, :activate, :deactivate, :test]

  def index
    @webhooks = @service.webhooks.order(created_at: :desc)
  end

  def show
  end

  def new
    @webhook = @service.webhooks.build
  end

  def create
    @webhook = @service.webhooks.build(webhook_params)
    @webhook.created_by = current_user

    if @webhook.save
      redirect_to [:admin, @service, @webhook], notice: "Webhook was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @webhook.update(webhook_params)
      redirect_to [:admin, @service, @webhook], notice: "Webhook was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @webhook.destroy
    redirect_to admin_service_webhooks_path(@service), notice: "Webhook was successfully deleted."
  end

  def activate
    @webhook.activate!
    redirect_to [:admin, @service, @webhook], notice: "Webhook activated."
  end

  def deactivate
    @webhook.deactivate!
    redirect_to [:admin, @service, @webhook], notice: "Webhook deactivated."
  end

  def test
    # Send a test webhook payload
    # In a real implementation, this would trigger the webhook with test data
    flash[:notice] = "Test webhook sent (implementation pending)"
    redirect_to [:admin, @service, @webhook]
  end

  private

  def set_service
    @service = Service.find(params[:service_id])
  end

  def set_webhook
    @webhook = @service.webhooks.find(params[:id])
  end

  def webhook_params
    params.require(:service_webhook).permit(:url, :event_type, :status)
  end

end
