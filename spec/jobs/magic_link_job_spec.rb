# frozen_string_literal: true

require "rails_helper"

RSpec.describe MagicLinkJob, type: :job do
  it "delivers a magic link email to the user" do
    user = create(:user)

    expect {
      described_class.perform_now(user, "test-token")
    }.to change { ActionMailer::Base.deliveries.size }.by(1)

    expect(ActionMailer::Base.deliveries.last.to).to eq([user.email])
  end

  it "puts the token it was handed into the link" do
    user = create(:user)

    described_class.perform_now(user, "test-token")

    expect(ActionMailer::Base.deliveries.last.body.encoded).to include("/auth/magic_link/test-token")
  end
end
