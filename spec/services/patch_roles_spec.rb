# frozen_string_literal: true

require "rails_helper"

# The `patches` claim and the directory field: the contract with Quilt.
RSpec.describe PatchRoles do
  let(:owner) { create(:user, :owner, :verified) }
  let(:user) { create(:user, :verified) }
  let!(:ganymede) { create(:patch, slug: "ganymede", name: "Project Ganymede") }
  let!(:europa) { create(:patch, slug: "europa", name: "Europa") }

  def role(patch, key) = patch.roles.find_or_create_by!(key:) { |record| record.name = key.titleize }

  def give(patch, key, to: user) = PatchRoleAssignment.create!(role: role(patch, key), assignee: to)

  def claim = described_class.for(user.reload_roles!)

  it "gives a role held directly" do
    give(europa, "viewer")

    expect(claim).to eq("europa" => ["viewer"])
  end

  it "gives a role held through an active group membership, and not through an expired one" do
    finance = create(:group, name: "Finance")
    create(:group_membership, group: finance, user:)
    give(ganymede, "finance", to: finance)
    alumni = create(:group, name: "Alumni")
    create(:group_membership, group: alumni, user:, expires_at: 1.day.from_now)
    give(europa, "viewer", to: alumni)

    travel 2.days do
      expect(claim).to eq("ganymede" => ["finance"])
    end
  end

  it "merges the lead key with the patch's own roles, sorted and unique, with the slugs sorted" do
    RoleGrants.grant!(user, "patch_lead", scope: "ganymede", by: owner, reason: "spec")
    give(ganymede, "viewer")
    give(ganymede, "reviewer")
    group = create(:group, name: "Reviewers")
    create(:group_membership, group:, user:)
    give(ganymede, "reviewer", to: group)
    give(europa, "viewer")

    expect(claim.to_json).to eq('{"europa":["viewer"],"ganymede":["lead","reviewer","viewer"]}')
  end

  it "is an empty object for a person with no patch role" do
    user.update!(is_staff: true)

    expect(claim).to eq({})
    expect(described_class.for(nil)).to eq({})
  end

  it "leaves out a removed assignment and a deleted role" do
    give(europa, "viewer").destroy!
    give(ganymede, "reviewer")
    role(ganymede, "reviewer").destroy!

    expect(claim).to eq({})
  end

  it "does not leak a role of another patch or another person" do
    give(europa, "viewer", to: create(:user, :verified))
    give(ganymede, "viewer")

    expect(claim).to eq("ganymede" => ["viewer"])
  end

  it "leaves out a revoked lead, and a lead of a program with no patch" do
    RoleGrants.grant!(user, "patch_lead", scope: "ganymede", by: owner, reason: "spec")
    RoleGrants.revoke!(user, "patch_lead", scope: "ganymede", by: owner, reason: "spec")
    expect(claim).to eq({})

    ActiveRecord::Base.connection.execute("DELETE FROM patches WHERE id = #{ganymede.id}")
    RoleGrants.grant!(user, "patch_lead", scope: "ganymede", by: owner, reason: "spec")
    expect(claim).to eq({})
  end
end
