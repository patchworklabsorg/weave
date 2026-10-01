# frozen_string_literal: true

require "rails_helper"

RSpec.describe PushPronounsToSlackJob do
  let(:service) { instance_double(SlackService) }

  before { allow(SlackService).to receive(:new).and_return(service) }

  it "sends the user's current pronouns to their Slack profile" do
    user = create(:user, slack_id: "U123", pronouns: "they/them")
    allow(service).to receive(:update_slack_pronouns).with("U123", "they/them").and_return(true)

    described_class.perform_now(user.id)

    expect(user.reload.slack_pronouns).to eq("they/them")
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

  it "does not record the value when Slack was not updated" do
    user = create(:user, slack_id: "U123", pronouns: "they/them")
    allow(service).to receive(:update_slack_pronouns).and_return(false)

    expect { described_class.perform_now(user.id) }.not_to have_enqueued_job(described_class)
    expect(user.reload.slack_pronouns).to be_nil
  end

  it "retries when Slack returns an error" do
    user = create(:user, slack_id: "U123", pronouns: "they/them")
    allow(service).to receive(:update_slack_pronouns).and_raise(Slack::Web::Api::Errors::SlackError, "fatal_error")

    expect { described_class.perform_now(user.id) }.to have_enqueued_job(described_class).with(user.id)
    expect(user.reload.slack_pronouns).to be_nil
  end

  it "retries when Slack rate limits the request" do
    user = create(:user, slack_id: "U123", pronouns: "they/them")
    response = instance_double(Faraday::Response, headers: { "retry-after" => "30" })
    allow(service).to receive(:update_slack_pronouns)
      .and_raise(Slack::Web::Api::Errors::TooManyRequestsError.new(response))

    expect { described_class.perform_now(user.id) }.to have_enqueued_job(described_class).with(user.id)
  end
end
