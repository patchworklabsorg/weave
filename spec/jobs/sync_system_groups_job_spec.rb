# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncSystemGroupsJob do
  it "syncs every user and records the job as the actor" do
    user = create(:user)
    # A role row written without RoleGrants (as raw SQL would), so no sync ran.
    UserRole.create!(user:, role: Role.fetch!("board"), granted_at: Time.current)

    described_class.perform_now

    membership = user.reload.group_memberships.sole
    expect(membership.group.slug).to eq("board")
    expect(membership.versions.last.whodunnit).to eq("SyncSystemGroupsJob")
  end
end
