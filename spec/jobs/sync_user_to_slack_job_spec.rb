# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncUserToSlackJob do
  let(:service) { instance_double(SlackService) }

  before do
    allow(SlackService).to receive(:new).and_return(service)
    allow(service).to receive(:send).with(:update_slack_profile_field, any_args)
  end

  it "links a guest found in Slack and keeps them pending" do
    user = create(:user, :verified, email: "guest@example.com")
    allow(service).to receive(:find_user_by_email).and_return("id" => "U1", "updated" => Time.now.to_i, "is_ultra_restricted" => true)

    described_class.perform_now(user.id)

    expect(user.reload.slack_id).to eq("U1")
    expect(user).to be_slack_pending
  end

  it "makes someone Slack reports as a regular member a member" do
    user = create(:user, :verified, email: "full@example.com")
    allow(service).to receive(:find_user_by_email).and_return("id" => "U2", "updated" => Time.now.to_i)

    described_class.perform_now(user.id)

    expect(user.reload).to be_slack_member
  end
end
