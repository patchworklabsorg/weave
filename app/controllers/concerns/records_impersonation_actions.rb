# frozen_string_literal: true

# Records what an admin does while impersonating a user, as Impersonation::Action
# rows on the open Impersonation (session[:impersonation_id], set by
# Admin::UsersController#impersonate).
#
# Every state-changing request (POST, PUT, PATCH, DELETE) is recorded, and so is
# every full HTML page the admin opens, so the log also shows what the admin
# looked at. Turbo stream, JSON and XHR GETs are left out: they are polling and
# partial updates, and would bury the page views. An impersonation keeps at most
# MAX_ACTIONS rows.
#
# Params are filtered with config.filter_parameters plus EXTRA_FILTERS, long
# values are cut, and the whole summary is capped at MAX_PARAMS_BYTES.
#
# Recording never breaks the request: a failure is logged and ignored.
#
# Include it before any other callback, so requests that a before_action stops
# (a redirect, for example) are recorded too.
module RecordsImpersonationActions
  extend ActiveSupport::Concern

  MAX_ACTIONS = 1_000
  MAX_PARAMS_BYTES = 4_096
  MAX_VALUE_LENGTH = 200
  # The OAuth code and PKCE verifier are matched exactly: a plain :code would
  # also hide fields like accept_code_of_conduct.
  EXTRA_FILTERS = [:cropped_image_data, :fingerprint, /\A(code|code_verifier)\z/].freeze
  DROPPED_PARAMS = %w[controller action format authenticity_token].freeze

  included do
    around_action :record_impersonation_action
  end

  private

  def record_impersonation_action
    impersonation_id = session[:impersonation_id] if session[:admin_id].present?
    return yield unless impersonation_id

    status = 500
    begin
      yield
      status = response.status
    ensure
      store_impersonation_action(impersonation_id, status)
    end
  end

  def store_impersonation_action(impersonation_id, status)
    return unless impersonation_action_recordable?
    return if Impersonation::Action.where(impersonation_id: impersonation_id).count >= MAX_ACTIONS

    Impersonation::Action.create!(
      impersonation_id: impersonation_id,
      http_method: request.request_method,
      path: request.path.first(255),
      controller_action: "#{controller_path}##{action_name}",
      status: status,
      params: impersonation_action_params
    )
  rescue => e
    Rails.logger.error("Could not record impersonation action #{request.request_method} #{request.path}: #{e.class}: #{e.message}")
  end

  def impersonation_action_recordable?
    return false if request.head?
    return true unless request.get?

    request.format.html? && !request.xhr? && request.headers["Turbo-Frame"].blank?
  end

  def impersonation_action_params
    filtered = ActiveSupport::ParameterFilter.new(EXTRA_FILTERS).filter(request.filtered_parameters.except(*DROPPED_PARAMS))
    summary = truncate_impersonation_values(filtered)
    return summary if summary.to_json.bytesize <= MAX_PARAMS_BYTES

    { "_truncated" => true, "keys" => summary.keys.first(50) }
  end

  def truncate_impersonation_values(value)
    case value
    when Hash then value.to_h { |key, nested| [key.to_s, truncate_impersonation_values(nested)] }
    when Array then value.first(20).map { |nested| truncate_impersonation_values(nested) }
    when String then value.first(MAX_VALUE_LENGTH)
    when ActionDispatch::Http::UploadedFile then "[FILE]"
    else value
    end
  end

end
