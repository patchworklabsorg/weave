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
      break_glass_approvals_required: 2,
      max_key_holders: 3
    )
  end
end
