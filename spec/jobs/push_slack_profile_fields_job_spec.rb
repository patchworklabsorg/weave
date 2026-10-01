# frozen_string_literal: true

require "rails_helper"

RSpec.describe PushSlackProfileFieldsJob do
  let(:service) { instance_double(SlackService) }

  before { allow(SlackService).to receive(:new).and_return(service) }

  it "sends the user's current profile fields to Slack" do
    user = create(:user, slack_id: "U123", slack_cost_center: "CC-1")
    expect(service).to receive(:push_profile_fields).with("U123", user)

    described_class.perform_now(user.id)
  end

  it "does nothing for a user who is not in Slack" do
    user = create(:user, slack_id: nil)
    expect(service).not_to receive(:push_profile_fields)

    described_class.perform_now(user.id)
  end

  it "retries when Slack returns an error" do
    user = create(:user, slack_id: "U123")
    allow(service).to receive(:push_profile_fields).and_raise(Slack::Web::Api::Errors::SlackError, "fatal_error")

    expect { described_class.perform_now(user.id) }.to have_enqueued_job(described_class).with(user.id)
  end
end
