# frozen_string_literal: true

require "rails_helper"

RSpec.describe OpenCallSchedulingDmJob do
  let(:service) { instance_double(SlackService, configured?: true) }
  let(:member) { create(:user, :verified, slack_id: "UMEMBER") }
  let(:reviewer) { create(:user, :identity_team, slack_id: "UREVIEW") }
  let(:verification) do
    create(:verification, user: member).tap do |v|
      VerificationFlow.start_pre_review(v, by: reviewer)
      VerificationFlow.approve_document(v, by: reviewer)
    end
  end

  before {
    # "Document OK" seals the image (see IdDocumentVault).
    active_key_set_without_holders
    allow(SlackService).to receive(:new).and_return(service)
  }

  it "opens a group DM with the member and the pre-reviewer, and logs it once" do
    expect(service).to receive(:post_group_dm)
      .with(%w[UMEMBER UREVIEW], a_string_including("<@UMEMBER>", "<@UREVIEW>", "agree a time"))
      .once.and_return("G123")

    described_class.perform_now(verification.id)
    described_class.perform_now(verification.id)

    event = verification.events.find_by(kind: "scheduling_dm_opened")
    expect(event.actor).to eq(reviewer)
    expect(event.data).to include("channel" => "G123")
  end

  it "does nothing when the member is not in Slack" do
    member.update!(slack_id: nil)
    expect(service).not_to receive(:post_group_dm)

    described_class.perform_now(verification.id)
  end

  it "does nothing when the pre-reviewer is not in Slack" do
    reviewer.update!(slack_id: nil)
    expect(service).not_to receive(:post_group_dm)

    described_class.perform_now(verification.id)
  end

  it "does nothing after the call time is set" do
    VerificationFlow.schedule_call(verification, by: reviewer, at: 2.days.from_now)
    expect(service).not_to receive(:post_group_dm)

    described_class.perform_now(verification.id)
  end

  it "stops without an event when Slack refuses, because the member still has the email" do
    allow(service).to receive(:post_group_dm).and_raise(Slack::Web::Api::Errors::SlackError.new("missing_scope"))

    expect { described_class.perform_now(verification.id) }.not_to raise_error
    expect(verification.events.where(kind: "scheduling_dm_opened")).to be_empty
  end
end
