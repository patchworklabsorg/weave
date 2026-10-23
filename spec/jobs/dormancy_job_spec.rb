# frozen_string_literal: true

require "rails_helper"

RSpec.describe DormancyJob do
  include ActiveJob::TestHelper

  let(:now) { Time.zone.local(2031, 6, 1, 12) }
  let(:user) { create(:user, :verified, created_at: Time.zone.local(2026, 1, 1)) }

  def sign_in_at(time)
    User::Session.create!(user:, session_token: SecureRandom.hex, created_at: time, last_seen_at: time,
                          expiration_at: time + 1.day)
  end

  def warning_mails
    enqueued_jobs.select { |job| job["arguments"][0..1] == %w[DataHandlingMailer dormancy_warning] }
  end

  it "sends the 60-day warning, then the 7-day warning, before the 5-year cutoff" do
    sign_in_at(Time.zone.local(2026, 6, 1, 12)) # cutoff 2031-06-01
    user

    travel_to(now - 61.days) { described_class.perform_now }
    expect(warning_mails).to be_empty

    travel_to(now - 59.days) { described_class.perform_now }
    travel_to(now - 58.days) { described_class.perform_now }
    expect(user.dormancy_warnings.pluck(:days_before)).to eq([60])

    travel_to(now - 6.days) { described_class.perform_now }
    expect(user.dormancy_warnings.pluck(:days_before)).to contain_exactly(60, 7)
    expect(warning_mails.size).to eq(2)
    expect(DeletionRequest.count).to eq(0)
  end

  it "sends the account to the human review after the cutoff, through the same pipeline" do
    sign_in_at(Time.zone.local(2026, 6, 1, 12))
    travel_to(now - 6.days) { described_class.perform_now }

    travel_to(now + 1.day) { described_class.perform_now }

    request = DeletionRequest.sole
    expect(request.source).to eq("dormancy")
    expect(request).to be_pending_review
  end

  it "always sends the last warning at least 7 days before the request" do
    sign_in_at(Time.zone.local(2026, 1, 1, 12))

    travel_to(now) { described_class.perform_now }
    expect(user.dormancy_warnings.pluck(:days_before)).to eq([7])
    expect(DeletionRequest.count).to eq(0)

    travel_to(now + 8.days) { described_class.perform_now }
    expect(DeletionRequest.count).to eq(1)
  end

  it "resets the clock on any sign-in and cancels an open dormancy request" do
    sign_in_at(Time.zone.local(2026, 1, 1, 12))
    travel_to(now) { described_class.perform_now }
    travel_to(now + 8.days) { described_class.perform_now }
    request = DeletionRequest.sole

    sign_in_at(now + 9.days)
    travel_to(now + 10.days) { described_class.perform_now }

    expect(request.reload).to be_cancelled
    expect(DeletionRequest.unfinished.count).to eq(0)
  end

  it "leaves active members alone" do
    sign_in_at(now - 1.year)

    travel_to(now) { described_class.perform_now }

    expect(user.dormancy_warnings).to be_empty
  end
end
