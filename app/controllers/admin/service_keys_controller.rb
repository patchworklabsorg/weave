# frozen_string_literal: true

class Admin::ServiceKeysController < Admin::BaseController
  before_action :set_service
  before_action :set_key, only: [:show, :edit, :update, :destroy, :revoke, :deprecate, :activate]

  def index
    @keys = @service.keys.order(created_at: :desc)
  end

  def show
    @recent_usages = @key.usages.recent.limit(50)
  end

  def new
    @key = @service.keys.build
  end

  def create
    @key = @service.keys.build(key_params)
    @key.created_by = current_user

    # Generate API key
    api_key = Service::Key.generate_api_key
    @key.api_key = api_key

    if @key.save
      # Show the API key once (only time it's available)
      flash[:api_key] = api_key
      flash[:notice] = "API key was successfully created. Make sure to copy it now - you won't be able to see it again!"
      redirect_to [:admin, @service, @key]
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @key.update(key_params)
      redirect_to [:admin, @service, @key], notice: "API key was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @key.destroy
    redirect_to admin_service_keys_path(@service), notice: "API key was successfully deleted."
  end

  def revoke
    @key.revoke!
    redirect_to [:admin, @service, @key], notice: "API key revoked."
  end

  def deprecate
    @key.deprecate!
    redirect_to [:admin, @service, @key], notice: "API key deprecated."
  end

  def activate
    @key.activate!
    redirect_to [:admin, @service, @key], notice: "API key activated."
  end

  private

  def set_service
    @service = Service.find(params[:service_id])
  end

  def set_key
    @key = @service.keys.find(params[:id])
  end

  def key_params
    params.require(:service_key).permit(:name, :expires_at)
  end

end
