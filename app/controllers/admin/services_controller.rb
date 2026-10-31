# frozen_string_literal: true

# Services in the admin panel: the apps that call the Weave API with a key
# (Service::Key) and get events by webhook (Service::Webhook).
#
# Any admin may look. Only a superadmin may change a service, its keys or its
# webhooks: a key reads the directory, and a webhook sends user data out of
# Weave, so each one is a grant of access to user data.
class Admin::ServicesController < Admin::BaseController
  include RequiresServiceSuperadmin

  before_action :set_service, only: [:show, :edit, :update, :destroy, :activate, :deactivate, :suspend]
  before_action :require_service_superadmin, except: [:index, :show]

  def index
    @services = Service.order(:name)
    if params[:search].present?
      term = "%#{Service.sanitize_sql_like(params[:search].to_s.strip)}%"
      @services = @services.where("name ILIKE :t OR description ILIKE :t", t: term)
    end
    @key_counts = Service::Key.usable.group(:service_id).count
    @webhook_counts = Service::Webhook.active.group(:service_id).count
  end

  def show
    @keys = @service.keys.order(created_at: :desc)
    @webhooks = @service.webhooks.order(:event_type, :created_at)
  end

  def new
    @service = Service.new
  end

  def create
    @service = Service.new(service_params)
    @service.created_by = current_user

    if @service.save
      redirect_to admin_service_path(@service), notice: "The service was created. Add an API key or a webhook next."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @service.update(service_params)
      redirect_to admin_service_path(@service), notice: "The service was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @service.destroy
    redirect_to admin_services_path, notice: "#{@service.name} was deleted with its keys and webhooks."
  end

  def activate
    @service.activate!
    redirect_to admin_service_path(@service), notice: "The service was activated."
  end

  def deactivate
    @service.deactivate!
    redirect_to admin_service_path(@service), notice: "The service was deactivated. Its keys and webhooks stop working until you activate it."
  end

  def suspend
    @service.suspend!
    redirect_to admin_service_path(@service), notice: "The service was suspended. Its keys and webhooks stop working until you activate it."
  end

  private

  def set_service
    @service = Service.find_by_public_param!(params[:id])
  end

  def service_params
    params.require(:service).permit(:name, :description)
  end

end
