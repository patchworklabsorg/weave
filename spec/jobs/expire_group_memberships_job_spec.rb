# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExpireGroupMembershipsJob do
  it "removes expired memberships and keeps the others" do
    forever = create(:group_membership)
    later = create(:group_membership, expires_at: 1.week.from_now)
    lapsed = create(:group_membership, expires_at: 1.day.from_now)

    travel 2.days do
      described_class.perform_now

      expect(Group::Membership.all).to contain_exactly(forever, later)
      expect(Group::Membership.exists?(lapsed.id)).to be(false)
    end
  end

  it "records the job as the actor on each removal" do
    lapsed = create(:group_membership, expires_at: 1.hour.from_now)

    travel 2.hours do
      described_class.perform_now
    end

    version = PaperTrail::Version.where(item_type: "Group::Membership", item_id: lapsed.id, event: "destroy").sole
    expect(version.whodunnit).to eq("ExpireGroupMembershipsJob")
  end

  it "does nothing on a second run" do
    create(:group_membership, expires_at: 1.hour.from_now)

    travel 2.hours do
      described_class.perform_now

      expect { described_class.perform_now }.not_to change(PaperTrail::Version, :count)
    end
  end
end
