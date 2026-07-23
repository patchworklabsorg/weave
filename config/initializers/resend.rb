# frozen_string_literal: true

# Resend is the transactional email provider used in production/staging (the
# `:resend` Action Mailer delivery method is set in config/environments/production.rb).
# Development and test never deliver through Resend — dev uses letter_opener_web
# and test uses the :test adapter — so no real mail leaves those environments.
Resend.api_key = ENV["RESEND_API_KEY"] || Rails.application.credentials.dig(:resend, :api_key)
