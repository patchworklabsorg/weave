# frozen_string_literal: true

require "rails_helper"

RSpec.describe JoinSlackChannelsJob do
  let(:service) { instance_double(SlackService, configured?: true) }

  before { allow(SlackService).to receive(:new).and_return(service) }

  it "adds the member to every member channel" do
    allow(service).to receive(:add_to_channels).with("U1").and_return({})

    expect { described_class.perform_now("U1") }.not_to have_enqueued_job(described_class)
  end

  it "tries the failed channels again later" do
    allow(service).to receive(:add_to_channels).with("U1").and_return("C2" => "ratelimited")

    expect { described_class.perform_now("U1") }
      .to have_enqueued_job(described_class).with("U1", ["C2"], attempt: 2)
  end

  it "gives up after the last attempt" do
    allow(service).to receive(:add_to_channels).with("U1", ["C2"]).and_return("C2" => "invalid_auth")

    expect { described_class.perform_now("U1", ["C2"], attempt: described_class::ATTEMPTS) }
      .not_to have_enqueued_job(described_class)
  end

  it "does nothing when Slack is not configured" do
    allow(service).to receive(:configured?).and_return(false)
    expect(service).not_to receive(:add_to_channels)

    described_class.perform_now("U1")
  end
end
