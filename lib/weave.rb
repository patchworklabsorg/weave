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
  PRIVACY_POLICY_URL = "https://patchworklabs.org/privacy"
  # The public "What we do with your data" page. Every page that collects or
  # handles identity, verification or demographics data links to it.
  DATA_PAGE_URL = "https://patchworklabs.org/your-data"
  STAGING = "staging"

  class << self
    def data_page_url = DATA_PAGE_URL

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

    # The WebAuthn origin (config/initializers/webauthn.rb). Production and
    # staging use url. Development uses WEBAUTHN_ORIGIN, or else localhost on
    # PORT (foreman's bin/dev sets PORT=5000), or else port 3000. Test always
    # uses http://localhost:3000.
    def webauthn_origin(rails_env: Rails.env, env: ENV)
      if rails_env.to_s == "production"
        url(env)
      elsif rails_env.to_s == "development"
        env.fetch("WEBAUTHN_ORIGIN") { "http://localhost:#{env.fetch('PORT', 3000)}" }
      else
        "http://localhost:3000"
      end
    end

    # Prefix of the Patchwork Labs ID (User#p_id, the OIDC `sub`). Staging IDs
    # start with SPWL so a sandbox identity can never pass for a real one.
    def p_id_prefix(env = ENV)
      staging?(env) ? "SPWL" : "PWL"
    end

    # Who may receive mail, from the `mail_allowlist` credential: a list (or a
    # comma-separated string) of "@domain" entries and exact addresses, returned
    # downcased. nil means "deliver to anyone". Staging fails closed: without the
    # credential it allows nobody, so a missing entry never mails real people.
    def mail_allowlist(credentials: Rails.application.credentials, env: ENV)
      entries = credentials[:mail_allowlist]
      return (staging?(env) ? [] : nil) if entries.nil?

      Array(entries).flat_map { |entry| entry.to_s.split(",") }.map { |entry| entry.strip.downcase }.reject(&:empty?)
    end

    # Email domains that may not sign up, from the `signup_blocked_domains`
    # credential: a list (or a comma-separated string) of domains, returned
    # downcased without a leading "@". The list lives in credentials and not in
    # this public repository, so it stays private. Empty without the credential.
    def signup_blocked_domains(credentials: Rails.application.credentials)
      Array(credentials[:signup_blocked_domains])
        .flat_map { |entry| entry.to_s.split(",") }
        .map { |entry| entry.strip.downcase.delete_prefix("@") }
        .reject(&:empty?)
    end

    # True when the address is on a blocked domain or one of its subdomains.
    def signup_blocked?(email, credentials: Rails.application.credentials)
      _, at, domain = email.to_s.strip.downcase.rpartition("@")
      return false if at.empty? || domain.empty?

      signup_blocked_domains(credentials: credentials).any? do |blocked|
        domain == blocked || domain.end_with?(".#{blocked}")
      end
    end

    # Domain mail is sent from. It must be verified with the mail provider, and
    # the provider's API key may be restricted to it, so staging sets its own.
    def mail_domain(env = ENV)
      value = env["MAIL_DOMAIN"].to_s.strip
      value.empty? ? PRODUCTION_HOST : value
    end

    def mail_address(env = ENV)
      "hi@#{mail_domain(env)}"
    end

    def mail_from(env = ENV)
      "Weave <#{mail_address(env)}>"
    end

  end
end
