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
gem "kamal", require: false              # Docker container deployment
gem "thruster", require: false           # HTTP asset caching/compression and X-Sendfile acceleration
gem "faraday"                            # Web requests
gem "okcomputer" # Health checks
gem "benchmark" # Removed from Ruby 4.0 default gems; okcomputer requires it in production

###############################################################################
# FRONTEND & UI
###############################################################################
gem "propshaft"                          # Modern asset pipeline
gem "importmap-rails"                    # JavaScript with ESM import maps
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
# gem "webauthn", "~> 3.4"                 # WebAuthn support - TODO: Implement if needed
gem "doorkeeper"                         # OAuth 2.0 provider
gem "doorkeeper-openid_connect"          # OIDC id_tokens on top of Doorkeeper
gem "rack-attack"                        # Rate limiting
gem "rack-cors"                          # CORS management
gem "validates_email_format_of"          # Email validation
gem "disposable_mail"                    # Block disposable email domains
gem "lockbox"                            # Encryption
gem "blind_index"                        # Encrypted search
gem "geocoder"
gem "countries", "~> 8.0" # ISO 3166 country codes

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
gem "pg_search"                          # Full-text search
gem "acts_as_paranoid"                   # Soft deletions
gem "paper_trail"                        # Track changes to models
gem "strong_migrations", "~> 2.3"        # Safer database migrations

###############################################################################
# URL & IDENTIFICATION
###############################################################################
gem "encoded_ids", "~> 1.1"              # Stripe-style public IDs
gem "friendly_id"                        # URL slugs

###############################################################################
# STATE MACHINES & ERROR HANDLING
###############################################################################
gem "aasm"                               # State machines
gem "safely_block"                       # Error handling

###############################################################################
# FILE & IMAGE PROCESSING
###############################################################################
gem "image_processing", "~> 1.2" # Active Storage image transformations
gem "active_storage_validations" # File validations
gem "rqrcode" # QR code generation

###############################################################################
# EMAIL & COMMUNICATION
###############################################################################
gem "premailer-rails"                    # CSS to inline styles for emails
gem "email_reply_parser"                 # Parse email replies
gem "slack-ruby-client"                  # Slack API integration
gem "slocks", "~> 0.1.2"                 # Block Kit templates (.slocks views)
gem "resend"                             # Transactional email delivery (production)

###############################################################################
# BROWSER & SECURITY
###############################################################################
gem "browser", "~> 6.2"                  # Browser detection
gem "invisible_captcha"                  # Bot protection

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
gem "dotenv-rails"                       # Environment variables

###############################################################################
# PLATFORM COMPATIBILITY
###############################################################################
gem "tzinfo-data", platforms: %i[windows jruby]

##############################################################################
# API Documentation
##############################################################################
gem "rswag"
gem "rspec-rails"

###############################################################################
# DEVELOPMENT & TEST DEPENDENCIES
###############################################################################
group :development, :test do
  # Debugging
  gem "debug"

  # Test data & matchers
  gem "factory_bot_rails"
  gem "shoulda-matchers"

  # Security & Code Quality
  gem "brakeman", require: false # Security analysis
  gem "rubocop-rails-omakase", require: false # Ruby styling
  gem "rubocop-capybara", "~> 2.22", ">= 2.22.1"
  gem "relaxed-rubocop"
  gem "overcommit", require: false # Git hooks
  gem "rubocop-rspec_rails", "~> 2.31"
  gem "rubocop-rspec", "~> 3.6"


  # Performance
  gem "query_count" # SQL query counter

  # Code Quality
  gem "bullet" # N+1 query detection
end

group :development do
  # Development Tools
  gem "actual_db_schema"                 # Rolls back phantom migrations
  gem "annotaterb"                       # Annotate models
  gem "web-console"                      # Interactive console
  gem "listen", "~> 3.9"                 # File watcher
  gem "letter_opener_web"                # Preview emails
  gem "foreman"                          # Process manager
  gem "awesome_print"                    # Pretty print objects
  gem "rack-mini-profiler", "~> 4.0", require: false # Performance profiling

  # IDE Support
  gem "solargraph" # Ruby language server
  gem "solargraph-rails", "~> 1.2.4", require: false
  gem "htmlbeautifier", require: false # ERB formatting
end

group :test do
  # System Testing
  gem "capybara"
  gem "selenium-webdriver"

  # Enables `assigns` and `assert_template` in controller specs
  gem "rails-controller-testing"
end

gem "stackprof"

# Analytics/ML gems - commented out to reduce bloat
# Uncomment and implement when needed for specific use cases:
# gem "rollups"              # Time-series data aggregation
# gem "prophet-rb"           # Time-series forecasting
# gem "anomaly_detection"    # Detect anomalies in data
# gem "breakout-detection"   # Detect breakouts/shifts in metrics
# gem "disco"                # Recommendations engine

gem "chartkick"
gem "mapkick-rb"
gem "phonelib"
