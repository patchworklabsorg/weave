# frozen_string_literal: true

# Read-only directory for OAuth apps. An app calls it with its own
# client_credentials token to check a user again without a browser session.
#
# The token must have the `directory` scope, must have no user, and the app's
# allowed scopes must list `directory`, so an admin has to turn the API on for
# each app. The API shows only what the app could already see in claims: users
# the app may serve (AppAccess), and only the groups and roles linked to it.
module Api
  module V1
    module Directory
      class BaseController < ActionController::API
        before_action -> { doorkeeper_authorize!(:directory) }
        before_action :require_directory_client

        private

        def current_application = doorkeeper_token.application

        def require_directory_client
          return if doorkeeper_token.resource_owner_id.nil? && current_application&.scopes&.exists?("directory")

          render json: { error: "insufficient_scope", error_description: "Use a client_credentials token of an app allowed the directory scope" },
                 status: :forbidden
        end

        def render_not_found
          render json: { error: "not_found" }, status: :not_found
        end

      end
    end
  end
end
