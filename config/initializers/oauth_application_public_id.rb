# frozen_string_literal: true

# Give OAuth applications a public id, like Service and the other models.
# Admin URLs use the hashid (/admin/oauth_applications/k5qx9z12) instead of the
# database id. This does not change the OAuth client_id (`uid`).
Rails.application.config.to_prepare do
  Doorkeeper::Application.include EncodedIds::HashidIdentifiable
  Doorkeeper::Application.include PublicParamLookup
  Doorkeeper::Application.set_public_id_prefix :app
  # The app launcher and access requests (see OauthApplicationLauncher).
  Doorkeeper::Application.include OauthApplicationLauncher
end
