# frozen_string_literal: true

require "rails_helper"

RSpec.describe SlackCodeOfConductAcceptedJob do
  let!(:user) { create(:user, slack_id: "U123") }
  let(:service) { instance_double(SlackService, configured?: true) }

  before { allow(SlackService).to receive(:new).and_return(service) }

  it "records acceptance and promotes the guest to a full member" do
    expect(service).to receive(:promote_to_member).with("U123").and_return({ ok: true })

    described_class.perform_now("U123")

    expect(user.reload.slack_coc_accepted_at).to be_present
  end

  it "makes them a full member once Slack confirms the promotion" do
    allow(service).to receive(:promote_to_member).and_return({ ok: true })

    expect { described_class.perform_now("U123") }.to change { user.reload.slack_membership }.from("pending").to("member")
  end

  it "does nothing without a Slack user id" do
    expect(service).not_to receive(:promote_to_member)
    described_class.perform_now(nil)
  end

  it "still records acceptance even if promotion fails" do
    allow(service).to receive(:promote_to_member).and_return({ ok: false, error: "user_not_found" })
    described_class.perform_now("U123")
    expect(user.reload.slack_coc_accepted_at).to be_present
    expect(user).to be_slack_pending
  end
end
