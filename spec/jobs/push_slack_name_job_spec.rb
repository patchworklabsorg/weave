# frozen_string_literal: true

require "rails_helper"

RSpec.describe PushSlackNameJob do
  let(:slack) { instance_double(SlackService) }
  let!(:user) { create(:user, first_name: "Ada", last_name: "Lovelace", slack_id: "U1") }

  before { allow(SlackService).to receive(:new).and_return(slack) }

  it "sets only the Slack display name when there is a nickname" do
    expect(slack).to receive(:update_slack_profile_name).with("U1", display_name: "ada")

    described_class.perform_now(user.id, nickname: "ada")
  end

  it "sets the Slack first and last name to the preferred name otherwise" do
    expect(slack).to receive(:update_slack_profile_name).with("U1", first_name: "Ada", last_name: "Lovelace")

    described_class.perform_now(user.id)
  end

  it "does nothing for a user who is not in Slack" do
    user.update!(slack_id: nil)
    expect(slack).not_to receive(:update_slack_profile_name)

    described_class.perform_now(user.id)
  end
end
