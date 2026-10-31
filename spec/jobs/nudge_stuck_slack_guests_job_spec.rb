# frozen_string_literal: true

require "rails_helper"

RSpec.describe NudgeStuckSlackGuestsJob do
  let!(:stuck) { create(:user, :verified, slack_id: "U1", slack_joined_at: 3.days.ago) }

  let(:slack) { instance_double(SlackService, configured?: true, active_guest?: true) }

  before { allow(SlackService).to receive(:new).and_return(slack) }

  def nudged
    described_class.candidates.to_a
  end

  it "reminds a guest who joined over two days ago and never accepted" do
    expect { described_class.perform_now }
      .to have_enqueued_job(CodeOfConductRequestJob).with(stuck.id, reason: :onboarding)
  end

  it "does nothing when Slack is not configured" do
    allow(slack).to receive(:configured?).and_return(false)

    expect { described_class.perform_now }.not_to have_enqueued_job(CodeOfConductRequestJob)
  end

  it "skips a guest who left the Slack" do
    allow(slack).to receive(:active_guest?).with("U1").and_return(false)

    expect { described_class.perform_now }.not_to have_enqueued_job(CodeOfConductRequestJob)
  end

  it "skips a locked account" do
    stuck.update!(locked_at: Time.current)

    expect(nudged).to be_empty
  end

  it "waits two days after the guest joined" do
    stuck.update!(slack_joined_at: 1.day.ago)

    expect(nudged).to be_empty
  end

  it "skips a guest with no join time" do
    stuck.update!(slack_joined_at: nil)

    expect(nudged).to be_empty
  end

  it "leaves out guests who joined over two weeks ago, unless asked" do
    stuck.update!(slack_joined_at: 3.weeks.ago)

    expect(nudged).to be_empty
    expect(described_class.candidates(since: nil)).to eq([stuck])
  end

  it "skips a guest with no birthday or under the minimum age" do
    stuck.update_columns(birthday: nil) # rubocop:disable Rails/SkipsModelValidations
    expect(nudged).to be_empty

    stuck.update_columns(birthday: 12.years.ago.to_date) # rubocop:disable Rails/SkipsModelValidations
    expect(nudged).to be_empty
  end

  it "reminds a minor whose guardian has not consented" do
    stuck.update_columns(birthday: 15.years.ago.to_date) # rubocop:disable Rails/SkipsModelValidations

    expect { described_class.perform_now }.to have_enqueued_job(CodeOfConductRequestJob)
  end

  it "spaces out the reminders" do
    create(:user, :verified, slack_id: "U9", slack_joined_at: 3.days.ago)

    freeze_time do
      expect { described_class.perform_now }
        .to have_enqueued_job(CodeOfConductRequestJob).at(Time.current).once
        .and have_enqueued_job(CodeOfConductRequestJob).at(2.seconds.from_now).once
    end
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
