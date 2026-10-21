# frozen_string_literal: true

source "https://rubygems.org"

ruby File.read(File.join(File.dirname(__FILE__), ".ruby-version")).strip

###############################################################################
# CORE RAILS AND PRIMARY DEPENDENCIES
###############################################################################
gem "rails", "~> 8.1"
gem "pg", "~> 1.5", ">= 1.5.9"           # PostgreSQL database
gem "puma", ">= 5.0"                     # Web server
gem "bootsnap", require: false           # Reduces boot times through caching
gem "thruster", require: false           # HTTP asset caching/compression and X-Sendfile acceleration
gem "faraday"                            # Web requests
gem "okcomputer" # Health checks
gem "benchmark" # Removed from Ruby 4.0 default gems; okcomputer requires it in production

###############################################################################
# FRONTEND & UI
###############################################################################
gem "propshaft"                          # Modern asset pipeline
gem "turbo-rails"                        # Hotwire's SPA-like page accelerator
gem "stimulus-rails"                     # Hotwire's modest JavaScript framework
gem "tailwindcss-rails", "~> 4.2"        # CSS framework
gem "tailwindcss-ruby", "~> 4.1", platforms: :ruby
gem "jbuilder"                           # Build JSON APIs
gem "jsbundling-rails", "~> 1.0"

###############################################################################
# SECURITY & AUTHENTICATION
###############################################################################
gem "bcrypt", "~> 3.1.7" # Secure password hashing
gem "webauthn", "~> 3.4" # Passkey sign-in (WebAuthn)
gem "doorkeeper"                         # OAuth 2.0 provider
gem "doorkeeper-openid_connect"          # OIDC id_tokens on top of Doorkeeper
gem "rack-attack"                        # Rate limiting
gem "validates_email_format_of"          # Email validation
gem "disposable_mail"                    # Block disposable email domains
gem "lockbox"                            # Encryption
gem "blind_index"                        # Encrypted search
gem "geocoder"
gem "countries", "~> 8.0" # ISO 3166 country codes
gem "net-ldap", "~> 0.20" # Active Directory password checks and changes (LDAPS)

###############################################################################
# BACKGROUND PROCESSING & CACHING
###############################################################################
gem "redis"
gem "solid_queue"                        # Database-backed Active Job adapter
gem "solid_cable"                        # Database-backed Action Cable
gem "mission_control-jobs"               # Job monitoring

###############################################################################
# DATABASE TOOLS
###############################################################################
gem "acts_as_paranoid"                   # Soft deletions
gem "paper_trail"                        # Track changes to models
gem "strong_migrations", "~> 2.3"        # Safer database migrations

###############################################################################
# URL & IDENTIFICATION
###############################################################################
gem "encoded_ids", "~> 1.1" # Stripe-style public IDs

###############################################################################
# STATE MACHINES & ERROR HANDLING
###############################################################################
gem "aasm" # State machines

###############################################################################
# FILE & IMAGE PROCESSING
###############################################################################
gem "active_storage_validations" # File validations

###############################################################################
# EMAIL & COMMUNICATION
###############################################################################
gem "premailer-rails"                    # CSS to inline styles for emails
gem "slack-ruby-client"                  # Slack API integration
gem "resend"                             # Transactional email delivery (production)

###############################################################################
# BROWSER & SECURITY
###############################################################################
gem "browser", "~> 6.2" # Browser detection

###############################################################################
# MONITORING & ANALYTICS
###############################################################################
gem "ahoy_matey"                         # Analytics
gem "ahoy_email"                         # Email analytics
gem "blazer"                             # BI dashboard
gem "audits1984"                         # Audit logging
gem "console1984"                        # Console access auditing
gem "irb"                                # IRB (was pinned for Console1984 compatibility)

###############################################################################
# FEATURE FLAGS & CONFIGURATION
###############################################################################
gem "flipper"                            # Feature flags
gem "flipper-active_record"              # ActiveRecord adapter for Flipper
gem "flipper-ui"                         # UI for Flipper

###############################################################################
# PLATFORM COMPATIBILITY
###############################################################################
gem "tzinfo-data", platforms: %i[windows jruby]

###############################################################################
# DEVELOPMENT & TEST DEPENDENCIES
###############################################################################
group :development, :test do
  # Debugging
  gem "debug"

  # Environment variables from .env files
  gem "dotenv-rails"

  # Test framework, data and matchers
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "shoulda-matchers"

  # Security & Code Quality
  gem "brakeman", require: false # Security analysis
  gem "rubocop-rails-omakase", require: false # Ruby styling
  gem "rubocop-capybara", "~> 3.1"
  gem "relaxed-rubocop"
  gem "rubocop-rspec_rails", "~> 2.31"
  gem "rubocop-rspec", "~> 3.6"

  # Code Quality
  gem "bullet" # N+1 query detection
end

group :development do
  # Development Tools
  gem "actual_db_schema"                 # Rolls back phantom migrations
  gem "annotaterb"                       # Annotate models
  gem "web-console"                      # Interactive console
  gem "letter_opener_web"                # Preview emails
  gem "rack-mini-profiler", "~> 5.0", require: false # Performance profiling
end

group :test do
  # System Testing
  gem "capybara"
  gem "selenium-webdriver"

  # Enables `assigns` and `assert_template` in controller specs
  gem "rails-controller-testing"
end

# Analytics/ML gems - commented out to reduce bloat
# Uncomment and implement when needed for specific use cases:
# gem "rollups"              # Time-series data aggregation
# gem "prophet-rb"           # Time-series forecasting
# gem "anomaly_detection"    # Detect anomalies in data
# gem "breakout-detection"   # Detect breakouts/shifts in metrics
# gem "disco"                # Recommendations engine

gem "mapkick-rb"
gem "phonelib"
