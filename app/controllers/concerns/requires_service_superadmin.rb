# frozen_string_literal: true

# Changes to services, their API keys and their webhooks are for a superadmin
# only (see Admin::ServicesController).
module RequiresServiceSuperadmin
  extend ActiveSupport::Concern

  private

  def require_service_superadmin
    return if current_user.superadmin?

    back = @service&.persisted? ? admin_service_path(@service) : admin_services_path
    redirect_to back, alert: "Only a superadmin can change services, API keys and webhooks."
  end
end
