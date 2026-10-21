# frozen_string_literal: true

require "rails_helper"

RSpec.describe NudgeStuckSlackGuestsJob do
  let!(:stuck) { create(:user, :verified, slack_id: "U1", slack_joined_at: 3.days.ago) }

  before { Flipper.enable(:start_here_nudge) }

  def nudged
    described_class.candidates.to_a
  end

  it "reminds a guest who joined over two days ago and never accepted" do
    expect { described_class.perform_now }
      .to have_enqueued_job(CodeOfConductRequestJob).with(stuck.id, reason: :onboarding)
  end

  it "does nothing while the flag is off" do
    Flipper.disable(:start_here_nudge)

    expect { described_class.perform_now }.not_to have_enqueued_job(CodeOfConductRequestJob)
  end

  it "waits two days after the guest joined" do
    stuck.update!(slack_joined_at: 1.day.ago)

    expect(nudged).to be_empty
  end

  it "counts a guest with no join time as joined long ago" do
    stuck.update!(slack_joined_at: nil)

    expect(nudged).to eq([stuck])
  end

  it "reminds a guest only once" do
    stuck.update!(slack_coc_requested_at: 1.day.ago)

    expect(nudged).to be_empty
  end

  it "skips people who accepted, full members, exempt users and people not in the Slack" do
    stuck.update!(slack_coc_accepted_at: 1.hour.ago)
    create(:user, :verified, slack_id: "U2", slack_joined_at: 3.days.ago, slack_membership: "member")
    create(:user, :verified, slack_id: "U3", slack_joined_at: 3.days.ago, code_of_conduct_exempt: true)
    create(:user, :verified, slack_id: nil)

    expect(nudged).to be_empty
  end
end
