# frozen_string_literal: true

require "rails_helper"

RSpec.describe RunDeletionPipelineJob do
  it "runs the pipeline for an approved request" do
    request = create(:deletion_request, :approved)

    described_class.perform_now(request.id)

    expect(request.reload).to be_completed
    expect(request.runs.sole.outcome).to eq("completed")
  end

  it "does nothing for a request that waits for review" do
    request = create(:deletion_request)

    described_class.perform_now(request.id)

    expect(request.reload).to be_pending_review
    expect(User.exists?(request.user_id)).to be(true)
  end

  it "cancels a dormancy request when the member signed in after it" do
    user = create(:user, :verified)
    request = create(:deletion_request, :approved, user:, source: "dormancy", requested_at: 1.day.ago)
    User::Session.create!(user:, session_token: SecureRandom.hex, last_seen_at: Time.current, expiration_at: 1.day.from_now)

    described_class.perform_now(request.id)

    expect(request.reload).to be_cancelled
    expect(User.exists?(user.id)).to be(true)
  end
end
