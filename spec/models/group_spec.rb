# frozen_string_literal: true

# == Schema Information
#
# Table name: groups
# Database name: primary
#
#  id            :bigint           not null, primary key
#  deleted_at    :datetime
#  description   :text
#  kind          :string           default("manual"), not null
#  name          :string           not null
#  slug          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  created_by_id :bigint
#
# Indexes
#
#  index_groups_on_created_by_id  (created_by_id)
#  index_groups_on_deleted_at     (deleted_at)
#  index_groups_on_name           (name) UNIQUE WHERE (deleted_at IS NULL)
#  index_groups_on_slug           (slug) UNIQUE WHERE (deleted_at IS NULL)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#
require "rails_helper"

RSpec.describe Group do
  describe "slug" do
    it "is made from the name when left empty" do
      group = create(:group, name: "Board Members")

      expect(group.slug).to eq("board-members")
    end

    it "keeps a slug that was given" do
      expect(create(:group, name: "Engineering", slug: "eng").slug).to eq("eng")
    end

    it "rejects a slug with characters that apps can't rely on" do
      group = build(:group, slug: "Eng Team!")

      expect(group).not_to be_valid
      expect(group.errors[:slug]).to be_present
    end

    it "can't change after creation, because apps see it" do
      group = create(:group, slug: "eng")

      expect(group.update(slug: "engineering")).to be(false)
      expect(group.reload.slug).to eq("eng")
    end

    it "is unique among live groups" do
      create(:group, slug: "eng")

      expect(build(:group, slug: "eng")).not_to be_valid
    end

    it "is free again once the group that had it is deleted" do
      create(:group, name: "Engineering", slug: "eng").destroy

      expect(create(:group, name: "Engineering", slug: "eng")).to be_persisted
    end
  end

  it "rejects a name that a live group already has, in any case" do
    create(:group, name: "Engineering")

    expect(build(:group, name: "engineering", slug: "eng-2")).not_to be_valid
  end

  describe "#users" do
    it "lists only members whose membership has not expired" do
      group = create(:group)
      current = create(:group_membership, group: group).user
      lapsed = create(:group_membership, group: group, expires_at: 1.day.from_now)
      lapsed.update_column(:expires_at, 1.minute.ago) # rubocop:disable Rails/SkipsModelValidations

      expect(group.users).to contain_exactly(current)
    end
  end

  describe "deletion" do
    it "is soft and removes the memberships, so the members lose access" do
      group = create(:group)
      user = create(:group_membership, group: group).user

      group.destroy

      expect(described_class.with_deleted.find(group.id).deleted_at).to be_present
      expect(user.reload.groups).to be_empty
      expect(Group::Membership.where(group_id: group.id)).to be_empty
    end
  end

  it "allows hand edits only on manual groups" do
    expect(build(:group).editable?).to be(true)
    expect(build(:group, :system).editable?).to be(false)
  end
end
