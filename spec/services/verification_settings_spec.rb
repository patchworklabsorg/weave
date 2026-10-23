# frozen_string_literal: true

require "rails_helper"

# The values Jasper locked on 2026-10-12 (see config/kyc/verification.yml).
# Counsel can still change them in the config. Then change this spec too.
RSpec.describe VerificationSettings do
  it "uses the locked values" do
    expect(described_class).to have_attributes(
      failed_call_cooldown: 14.days,
      failed_calls_before_escalation: 2,
      purge_image_after_pass: 7.days,
      member_notice_delay: 72.hours,
      max_fraud_delay: 30.days,
      break_glass_handoff_ttl: 30.minutes,
      break_glass_approvals_required: 2,
      max_key_holders: 3
    )
  end

  describe ".hardware_keys_per_holder" do
    around do |example|
      saved = ENV.fetch("KYC_HARDWARE_KEYS_PER_HOLDER", nil)
      ENV["KYC_HARDWARE_KEYS_PER_HOLDER"] = "1"
      example.run
    ensure
      saved.nil? ? ENV.delete("KYC_HARDWARE_KEYS_PER_HOLDER") : ENV["KYC_HARDWARE_KEYS_PER_HOLDER"] = saved
    end

    def config_for(env) = Rails.application.config_for(described_class::PATH, env:)

    it "is locked at 2 in the production config, which staging also runs" do
      expect(config_for("production").dig(:key_custody, :hardware_keys_per_holder)).to eq(2)
    end

    it "stays 2 in production even when the override is set" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("production"))

      expect(described_class.hardware_keys_per_holder).to eq(2)
    end

    it "stays 2 in test even when the override is set" do
      expect(described_class.hardware_keys_per_holder).to eq(2)
    end

    it "takes the override in development only" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("development"))

      expect(described_class.hardware_keys_per_holder).to eq(1)
    end

    it "is 2 in development without the override" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("development"))
      ENV.delete("KYC_HARDWARE_KEYS_PER_HOLDER")

      expect(described_class.hardware_keys_per_holder).to eq(2)
    end

    it "refuses an override that is not 1 to 2" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new("development"))

      %w[0 3 two].each do |value|
        ENV["KYC_HARDWARE_KEYS_PER_HOLDER"] = value
        expect { described_class.hardware_keys_per_holder }.to raise_error(ArgumentError, /1 to 2/)
      end
    end
  end
end
