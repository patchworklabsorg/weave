# frozen_string_literal: true

# Which deployment of Weave this process is, and where it is served from.
#
# Production and staging run the same image with RAILS_ENV=production, so
# staging exercises exactly the production code paths. WEAVE_ENV tells the two
# apart and APP_HOST gives staging its own hostname. Read them through these
# helpers rather than touching ENV directly.
#
# Required by hand from config/application.rb (and ignored by Zeitwerk): the
# credentials path and config/environments/production.rb need it before the
# autoloader exists. Every method takes the environment as an argument so the
# specs can exercise it without mutating ENV.
module Weave
  PRODUCTION_HOST = "weave.patchworklabs.org"
  STAGING = "staging"

  class << self
    def staging?(env = ENV)
      env["WEAVE_ENV"] == STAGING
    end

    # The name under config/credentials/ this deployment reads, or nil to keep
    # Rails' per-RAILS_ENV resolution. See lib/credentials_paths.rb.
    def credentials_deployment(env = ENV)
      STAGING if staging?(env)
    end

    # Public hostname: OIDC issuer, mailer links, canonical URL, Host allowlist.
    def host(env = ENV)
      value = env["APP_HOST"].to_s.strip
      value.empty? ? PRODUCTION_HOST : value
    end

    def url(env = ENV)
      "https://#{host(env)}"
    end

    # MAIL_ALLOWLIST as downcased entries ("@domain" or an exact address), or
    # nil when the variable is unset, which means "deliver to anyone". A set but
    # empty list allows nobody, so a blanked value fails closed.
    def mail_allowlist(env = ENV)
      return nil unless env.key?("MAIL_ALLOWLIST")

      env["MAIL_ALLOWLIST"].to_s.split(",").map { |entry| entry.strip.downcase }.reject(&:empty?)
    end

  end
end
