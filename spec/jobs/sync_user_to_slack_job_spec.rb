# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncUserToSlackJob do
  let(:service) { instance_double(SlackService) }

  before { allow(SlackService).to receive(:new).and_return(service) }

  # The link and membership rules are in spec/services/slack_service_linked_account_spec.rb.
  it "syncs the Weave ID through SlackService#sync_weave_id" do
    user = create(:user, :verified)
    expect(service).to receive(:sync_weave_id).with(user)

    described_class.perform_now(user.id)
  end

  it "stops when Slack is not configured" do
    user = create(:user, :verified)
    allow(service).to receive(:sync_weave_id).and_raise(SlackService::ConfigurationError)

    expect { described_class.perform_now(user.id) }.not_to raise_error
  end
end
