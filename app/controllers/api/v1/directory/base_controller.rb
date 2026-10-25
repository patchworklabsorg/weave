# frozen_string_literal: true

# Read-only directory for OAuth apps. An app calls it with its own
# client_credentials token to check a user again without a browser session.
#
# The token must have the `directory` scope, must have no user, and the app's
# allowed scopes must list `directory`, so an admin has to turn the API on for
# each app. A subclass can ask for another app scope (app_scope). The API
# shows only what the app could already see in claims: users the app may
# serve (AppAccess), and only the groups and roles linked to it.
module Api
  module V1
    module Directory
      class BaseController < ActionController::API
        class_attribute :app_scope, default: "directory"

        before_action -> { doorkeeper_authorize!(app_scope) }
        before_action :require_directory_client

        private

        def current_application = doorkeeper_token.application

        def require_directory_client
          return if doorkeeper_token.resource_owner_id.nil? && current_application&.scopes&.exists?(app_scope)

          render json: { error: "insufficient_scope", error_description: "Use a client_credentials token of an app allowed the #{app_scope} scope" },
                 status: :forbidden
        end

        def render_not_found
          render json: { error: "not_found" }, status: :not_found
        end

      end
    end
  end
end
