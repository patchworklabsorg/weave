# frozen_string_literal: true

require "rails_helper"

RSpec.describe Group::Membership do
  let(:group) { create(:group) }
  let(:user) { create(:user) }

  it "allows one membership per user and group" do
    create(:group_membership, group: group, user: user)

    duplicate = build(:group_membership, group: group, user: user)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:user_id]).to include("is already in this group")
  end

  it "rejects an expiry in the past" do
    membership = build(:group_membership, expires_at: 1.minute.ago)

    expect(membership).not_to be_valid
    expect(membership.errors[:expires_at]).to include("must be in the future")
  end

  describe "the active scope" do
    it "includes memberships with no expiry and with a future expiry, and excludes expired ones" do
      forever = create(:group_membership)
      later = create(:group_membership, expires_at: 1.week.from_now)
      lapsed = create(:group_membership, expires_at: 1.day.from_now)

      travel 2.days do
        expect(described_class.active).to contain_exactly(forever, later)
        expect(described_class.expired).to contain_exactly(lapsed)
        expect(lapsed.reload).to be_expired
      end
    end
  end

  it "gives a user their groups through unexpired memberships only" do
    kept = create(:group_membership, user: user).group
    create(:group_membership, user: user, expires_at: 1.hour.from_now)

    travel 2.hours do
      expect(user.reload.groups).to contain_exactly(kept)
    end
  end

  it "records a PaperTrail version, so removals stay on record" do
    membership = create(:group_membership)

    expect { membership.destroy }.to change(PaperTrail::Version, :count).by(1)
    expect(PaperTrail::Version.last.event).to eq("destroy")
  end
end
