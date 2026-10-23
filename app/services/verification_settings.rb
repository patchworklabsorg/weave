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

    def member_notice_delay = config.dig(:break_glass, :member_notice_hours).hours

    def max_fraud_delay = config.dig(:break_glass, :max_fraud_delay_days).days

    # How long the requester has to open a granted image (BreakGlass.open!).
    def break_glass_handoff_ttl = config.dig(:break_glass, :handoff_minutes).minutes

    # Key custody (see KeyCustody). The threshold is the number of approvals
    # a break-glass request needs, and the share count is the number of key
    # holders.
    def key_custody_threshold = break_glass_approvals_required

    def key_custody_share_count = max_key_holders

    # Hardware keys per key holder: LOCKED at 2 in config. Development only
    # can lower it with KYC_HARDWARE_KEYS_PER_HOLDER, for a local test with
    # fewer YubiKeys (for example 3 keys for 3 holders). Production, staging
    # (RAILS_ENV=production) and test ignore the variable.
    def hardware_keys_per_holder
      locked = config.dig(:key_custody, :hardware_keys_per_holder)
      return locked unless Rails.env.development? && ENV["KYC_HARDWARE_KEYS_PER_HOLDER"].present?

      count = Integer(ENV.fetch("KYC_HARDWARE_KEYS_PER_HOLDER"), exception: false)
      raise ArgumentError, "KYC_HARDWARE_KEYS_PER_HOLDER must be 1 to #{locked}." unless count&.between?(1, locked)

      count
    end

    def pending_share_ttl = config.dig(:key_custody, :pending_share_minutes).minutes

    def key_custody_challenge_ttl = config.dig(:key_custody, :challenge_minutes).minutes

    def require_user_verification? = config.dig(:key_custody, :require_user_verification) == true

    # For specs that change a value.
    def reset! = @config = nil

  end
end
