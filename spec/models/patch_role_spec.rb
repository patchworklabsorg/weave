# frozen_string_literal: true

require "rails_helper"

# A role that a superadmin defines for one patch. Apps see the key, so it never
# changes, and "lead" belongs to the patch_lead governance role.
RSpec.describe PatchRole do
  let(:patch) { create(:patch, slug: "ganymede") }

  it "needs a name and a key in the key format" do
    expect(patch.roles.build(key: "viewer", name: "")).not_to be_valid
    %w[Viewer view\ er -viewer viewer-].each do |key|
      expect(patch.roles.build(key:, name: "Viewer")).not_to be_valid, "expected #{key.inspect} to be refused"
    end
    expect(patch.roles.build(key: "finance:read", name: "Finance")).to be_valid
    expect(patch.roles.build(key: "quilt:viewer", name: "Quilt viewer")).to be_valid
  end

  it "refuses the reserved key lead" do
    role = patch.roles.build(key: "lead", name: "Lead")

    expect(role).not_to be_valid
    expect(role.errors[:key]).to include("is reserved for the patch lead")
  end

  it "keeps the key unique in a patch, and lets another patch use it" do
    patch.roles.create!(key: "viewer", name: "Viewer")

    expect(patch.roles.build(key: "viewer", name: "Viewer 2")).not_to be_valid
    expect(create(:patch, slug: "europa").roles.build(key: "viewer", name: "Viewer")).to be_valid
  end

  it "never changes the key, and keeps a version of each change" do
    role = patch.roles.create!(key: "viewer", name: "Viewer")

    expect(role.update(key: "reader")).to be(false)
    expect(role.errors[:key]).to include("can't be changed after the role is created")
    role.reload.update!(name: "Finance viewer")
    expect(role.versions.map(&:event)).to eq(%w[create update])
  end

  it "gives one assignment for each assignee, and goes with its assignments" do
    role = patch.roles.create!(key: "viewer", name: "Viewer")
    user = create(:user, :verified)
    PatchRoleAssignment.create!(role:, assignee: user)

    expect(PatchRoleAssignment.new(role:, assignee: user)).not_to be_valid
    expect { role.destroy! }.to change(PatchRoleAssignment, :count).by(-1)
  end

  it "refuses a system group, and takes a manual group" do
    role = patch.roles.create!(key: "quilt:viewer", name: "Quilt viewer")
    assignment = PatchRoleAssignment.new(role:, assignee: create(:group, :system, name: "Everyone", slug: "everyone-test"))

    expect(assignment).not_to be_valid
    expect(assignment.errors[:assignee]).to include("must be a manual group: a system group follows user attributes")
    expect(PatchRoleAssignment.new(role:, assignee: create(:group))).to be_valid
  end

  it "goes when the user or the group goes" do
    role = patch.roles.create!(key: "viewer", name: "Viewer")
    group = create(:group)
    PatchRoleAssignment.create!(role:, assignee: group)

    expect { group.destroy }.to change(PatchRoleAssignment, :count).by(-1)
  end
end
