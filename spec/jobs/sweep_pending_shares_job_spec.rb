# frozen_string_literal: true

require "rails_helper"

RSpec.describe SweepPendingSharesJob do
  let(:holder) { create(:user, :key_holder) }

  it "deletes the expired shares and keeps the live ones" do
    KeyCustody::PendingShares.put("break_glass:1:1", holder.id, SecureRandom.random_bytes(33), ttl: 1.minute)
    KeyCustody::PendingShares.put("break_glass:2:1", holder.id, SecureRandom.random_bytes(33), ttl: 10.minutes)

    travel(2.minutes) { described_class.perform_now }

    expect(KeyCustodyPendingShare.pluck(:memory_key)).to eq(["break_glass:2:1"])
  end

  it "deletes challenges that expired more than a day ago" do
    old = KeyCustody::Assertions.issue!(user: holder, purpose: "break_glass", subject: "brgl_old")

    travel(2.days) { described_class.perform_now }

    expect(KeyCustodyChallenge.exists?(old.id)).to be(false)
  end

  it "deletes a sealed break-glass handoff that the requester did not open in time" do
    requester = create(:user, :identity_team)
    record = granted_break_glass_record(create(:verification, :verified), requester:)
    expect(record.handoff_sealed_key).to be_present

    travel(VerificationSettings.break_glass_handoff_ttl + 1.minute) { described_class.perform_now }

    expect(record.reload.handoff_sealed_key).to be_nil
    expect(record.status).to eq(:expired)
  end

  it "runs every minute" do
    expect(Rails.root.join("config/recurring.yml").read).to include("class: SweepPendingSharesJob\n  schedule: every minute")
  end
end
