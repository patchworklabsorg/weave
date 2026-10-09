# frozen_string_literal: true

require "rails_helper"

RSpec.describe DemoteForCodeOfConductJob do
  let(:slack) { instance_double(SlackService, configured?: true, workspace_admin?: false, post_code_of_conduct: true) }
  let!(:user) do
    create(:user, :verified, slack_id: "U1", slack_membership: "member", slack_coc_requested_at: 3.weeks.ago)
  end

  before { allow(SlackService).to receive(:new).and_return(slack) }

  it "makes the member a guest and asks them again by DM and email" do
    allow(slack).to receive(:demote_to_guest).with("U1").and_return({ ok: true })
    expect(slack).to receive(:post_code_of_conduct)
      .with("U1", intro: a_string_including("now a guest account"), collect_name: false)

    expect { described_class.perform_now(user.id) }.to have_enqueued_mail(UserMailer, :code_of_conduct_request)

    user.reload
    expect(user).to be_slack_pending
    expect(user.slack_onboarding_step).to eq(:accept_code_of_conduct)
  end

  it "keeps the member when Slack refuses" do
    allow(slack).to receive(:demote_to_guest).and_return({ ok: false, error: "not_allowed" })

    expect { described_class.perform_now(user.id) }.not_to have_enqueued_mail(UserMailer, :code_of_conduct_request)
    expect(user.reload).to be_slack_member
  end

  it "skips someone who accepted in the meantime" do
    user.update!(slack_coc_accepted_at: 1.hour.ago)
    expect(slack).not_to receive(:demote_to_guest)

    described_class.perform_now(user.id)
  end

  it "skips Slack admins and owners" do
    allow(slack).to receive(:workspace_admin?).with("U1").and_return(true)
    expect(slack).not_to receive(:demote_to_guest)

    described_class.perform_now(user.id)
  end
end
