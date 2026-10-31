# frozen_string_literal: true

# OmniAuth signs a member in to another site so they can link that account as
# a social profile (see SocialProfile and SocialProfilesController). It is
# never a way to sign in to Weave.
#
# The request phase is POST /auth/:provider, which
# omniauth-rails_csrf_protection checks for the Rails CSRF token. The site
# sends the member back to GET /auth/:provider/callback.
#
# Each provider reads its OAuth client from the environment (GITHUB_CLIENT_ID,
# GITHUB_CLIENT_SECRET) or the credentials file (github.client_id,
# github.client_secret). A provider without both is not mounted, and the
# profile page does not offer it.
social_providers = %w[github].filter_map do |provider|
  client_id, client_secret = %w[client_id client_secret].map do |key|
    ENV["#{provider.upcase}_#{key.upcase}"].presence || Rails.application.credentials.dig(provider.to_sym, key.to_sym)
  end
  # Specs use OmniAuth's test mode, which still needs the strategy mounted.
  client_id, client_secret = "test-#{provider}-id", "test-#{provider}-secret" if Rails.env.test?
  [provider, client_id, client_secret] if client_id.present? && client_secret.present?
end

Rails.application.config.x.social_providers = social_providers.map(&:first)

Rails.application.config.middleware.use OmniAuth::Builder do
  # No OAuth scope: the public profile is enough, and Weave does not keep the
  # token.
  social_providers.each { |name, client_id, client_secret| provider name.to_sym, client_id, client_secret }
end

OmniAuth.config.logger = Rails.logger
# Send every failure (a denied consent, a bad state) to /auth/failure, also in
# development, where OmniAuth raises by default.
OmniAuth.config.on_failure = ->(env) { OmniAuth::FailureEndpoint.new(env).redirect_to_failure }
