# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncSystemGroupsJob do
  it "syncs every user and records the job as the actor" do
    user = create(:user)
    user.update_column(:is_board, true) # rubocop:disable Rails/SkipsModelValidations

    described_class.perform_now

    membership = user.reload.group_memberships.sole
    expect(membership.group.slug).to eq("board")
    expect(membership.versions.last.whodunnit).to eq("SyncSystemGroupsJob")
  end
end
