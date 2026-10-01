# frozen_string_literal: true

require "rails_helper"

RSpec.describe InviteToSlackJob do
  let(:service) do
    instance_double(SlackService, configured?: true, find_user_by_email: nil,
                                  invite_to_workspace: { ok: true, already_member: false })
  end

  before { allow(SlackService).to receive(:new).and_return(service) }

  it "invites a new member as a single-channel guest and records the invite" do
    user = create(:user, :verified)
    expect(service).to receive(:invite_to_workspace)
      .with(hash_including(email: user.email, guest: :single_channel))

    described_class.perform_now(user.id)

    expect(user.reload.slack_invited_at).to be_present
  end

  it "doesn't invite someone who is already a full member" do
    user = create(:user, :verified, slack_id: "U1", slack_membership: "member")
    expect(service).not_to receive(:invite_to_workspace)

    described_class.perform_now(user.id)
  end
end
