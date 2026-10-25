# frozen_string_literal: true

# The API keys of a service. Weave stores only a digest of a key, so the key
# exists in plain text only in the response that creates it: `create` renders
# it and never redirects.
class Admin::ServiceKeysController < Admin::BaseController
  include RequiresServiceSuperadmin

  before_action :set_service
  before_action :set_key, only: [:show, :edit, :update, :destroy, :revoke, :deprecate, :activate]
  before_action :require_service_superadmin, except: [:index, :show]

  # The keys are listed on the service page.
  def index
    redirect_to admin_service_path(@service, anchor: "keys")
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
    @key.api_key = Service::Key.generate_api_key

    if @key.save
      @plaintext_key = @key.api_key
      @recent_usages = []
      flash.now[:notice] = "API key was created. Copy it now: Weave shows it only once."
      render :show
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @key.update(key_params)
      redirect_to admin_service_key_path(@service, @key), notice: "API key was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @key.destroy
    redirect_to admin_service_path(@service, anchor: "keys"), notice: "API key was deleted."
  end

  def revoke
    @key.revoke!
    redirect_to admin_service_key_path(@service, @key), notice: "API key revoked. It stops working at once."
  end

  def deprecate
    @key.deprecate!
    redirect_to admin_service_key_path(@service, @key), notice: "API key deprecated. It still works, and each use is logged."
  end

  def activate
    @key.activate!
    redirect_to admin_service_key_path(@service, @key), notice: "API key activated."
  end

  private

  def set_service
    @service = Service.find_by_public_param!(params[:service_id])
  end

  def set_key
    @key = @service.keys.find_by_public_param!(params[:id])
  end

  def key_params
    params.require(:service_key).permit(:name, :expires_at)
  end

end
