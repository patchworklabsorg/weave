# frozen_string_literal: true

require "rails_helper"

RSpec.describe PushPronounsToSlackJob do
  let(:service) { instance_double(SlackService) }

  before { allow(SlackService).to receive(:new).and_return(service) }

  it "sends the user's current pronouns to their Slack profile" do
    user = create(:user, slack_id: "U123", pronouns: "they/them")
    expect(service).to receive(:update_slack_pronouns).with("U123", "they/them")

    described_class.perform_now(user.id)
  end

  it "sends nil to clear the Slack field" do
    user = create(:user, slack_id: "U123")
    expect(service).to receive(:update_slack_pronouns).with("U123", nil)

    described_class.perform_now(user.id)
  end

  it "does nothing for a user who is not in Slack" do
    user = create(:user, slack_id: nil)
    expect(service).not_to receive(:update_slack_pronouns)

    described_class.perform_now(user.id)
  end
end
