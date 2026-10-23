# frozen_string_literal: true

# The open values of identity verification, from config/kyc/verification.yml.
# Cooldowns, purge windows and break-glass limits live in config and not in
# code, so counsel can change them.
module VerificationSettings
  PATH = Rails.root.join("config/kyc/verification.yml")

  class << self
    def config = @config ||= Rails.application.config_for(PATH)

    def failed_call_cooldown = config.fetch(:failed_call_cooldown_days).days

    def failed_calls_before_escalation = config.fetch(:failed_calls_before_escalation)

    def purge_image_after_pass = config.fetch(:purge_image_days_after_pass).days

    def purge_image_after_close = config.fetch(:purge_image_days_after_close).days

    def max_image_size = config.fetch(:max_image_megabytes).megabytes

    def break_glass_approvals_required = config.dig(:break_glass, :approvals_required)

    def max_key_holders = config.dig(:break_glass, :max_key_holders)

    def break_glass_access = config.dig(:break_glass, :access_minutes).minutes

    def member_notice_delay = config.dig(:break_glass, :member_notice_hours).hours

    def max_fraud_delay = config.dig(:break_glass, :max_fraud_delay_days).days

    # For specs that change a value.
    def reset! = @config = nil

  end
end
