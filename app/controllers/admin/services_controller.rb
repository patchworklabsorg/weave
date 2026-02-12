# frozen_string_literal: true

class Admin::ServicesController < Admin::BaseController
  before_action :set_service, only: [:show, :edit, :update, :destroy, :activate, :deactivate, :suspend]

  def index
    @services = Service.all.includes(:created_by, :keys).order(created_at: :desc)
  end

  def show
    @keys = @service.keys.order(created_at: :desc)
    @webhooks = @service.webhooks.order(created_at: :desc)
  end

  def new
    @service = Service.new
  end

  def create
    @service = Service.new(service_params)
    @service.created_by = current_user

    if @service.save
      redirect_to [:admin, @service], notice: "Service was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @service.update(service_params)
      redirect_to [:admin, @service], notice: "Service was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @service.destroy
    redirect_to admin_services_path, notice: "Service was successfully deleted."
  end

  def activate
    @service.activate!
    redirect_to [:admin, @service], notice: "Service activated."
  end

  def deactivate
    @service.deactivate!
    redirect_to [:admin, @service], notice: "Service deactivated."
  end

  def suspend
    @service.suspend!
    redirect_to [:admin, @service], notice: "Service suspended."
  end

  private

  def set_service
    @service = Service.find(params[:id])
  end

  def service_params
    params.require(:service).permit(:name, :description, :status)
  end
end
