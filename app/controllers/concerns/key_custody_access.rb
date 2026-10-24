# frozen_string_literal: true

# Access to the key custody pages (see KeyCustody): identity team members,
# owners and board members can look. Each action checks its own rule: a key
# holder enrolls their own keys, an owner or a key holder runs the ceremony,
# and only key holders give shares.
#
# The JSON actions answer the key custody script in the browser
# (app/javascript/controllers/key_custody_controller.js). A share and a
# WebAuthn answer arrive in the JSON body, and the request log filters them
# (config/initializers/filter_parameter_logging.rb).
module KeyCustodyAccess
  extend ActiveSupport::Concern

  included do
    skip_before_action :require_identity_team
    before_action :require_key_custody_access
    rescue_from KeyCustody::Refused, with: :key_custody_refused
  end

  private

  def require_key_custody_access
    return if KeyCustody.can_view?(current_user)

    respond_to do |format|
      format.json { render json: { error: "Only the identity team, owners and board members can open this page." }, status: :forbidden }
      format.any { redirect_to root_path, alert: "Only the identity team, owners and board members can open this page." }
    end
  end

  def key_custody_refused(error)
    respond_to do |format|
      format.json { render json: { error: error.message }, status: :unprocessable_content }
      format.any { redirect_to identity_key_custody_path, alert: error.message }
    end
  end

  # A WebAuthn answer from the JSON body, as a Hash with String keys.
  def credential_param(name = :credential)
    value = params[name]
    value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h.to_hash : nil
  end

  def json_success(message, **extra)
    flash[:notice] = message
    render json: { message:, **extra }
  end

end
