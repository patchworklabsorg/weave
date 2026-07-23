# frozen_string_literal: true

require "rails_helper"

RSpec.describe MagicLinkJob, type: :job do
  it "delivers a magic link email to the user" do
    user = create(:user, magic_link_token: "test-token")

    expect {
      described_class.perform_now(user)
    }.to change { ActionMailer::Base.deliveries.size }.by(1)

    expect(ActionMailer::Base.deliveries.last.to).to eq([user.email])
  end
end
