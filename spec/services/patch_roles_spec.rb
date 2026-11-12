# frozen_string_literal: true

require "rails_helper"

# The `patches` claim and the directory field: the contract with Quilt.
RSpec.describe PatchRoles do
  let(:owner) { create(:user, :owner, :verified) }
  let(:user) { create(:user, :verified) }

  before do
    create(:patch, slug: "ganymede", name: "Project Ganymede")
    create(:patch, slug: "europa", name: "Europa")
  end

  def grant(key, scope) = RoleGrants.grant!(user, key, scope:, by: owner, reason: "spec")

  it "maps each patch slug to the sorted short role names, with the slugs sorted" do
    grant("patch_viewer", "europa")
    grant("patch_viewer", "ganymede")
    grant("patch_lead", "ganymede")

    result = described_class.for(user.reload_roles!)

    expect(result).to eq("europa" => ["viewer"], "ganymede" => %w[lead viewer])
    expect(result.keys).to eq(%w[europa ganymede])
    expect(result.to_json).to eq('{"europa":["viewer"],"ganymede":["lead","viewer"]}')
  end

  it "is an empty object for a person with no patch role" do
    user.update!(is_staff: true)

    expect(described_class.for(user.reload_roles!)).to eq({})
    expect(described_class.for(nil)).to eq({})
  end

  it "leaves out a revoked role" do
    grant("patch_viewer", "europa")
    grant("patch_lead", "ganymede")
    RoleGrants.revoke!(user, "patch_viewer", scope: "europa", by: owner, reason: "spec")

    expect(described_class.for(user.reload_roles!)).to eq("ganymede" => ["lead"])
  end

  it "leaves out a patch that does not exist" do
    # A patch lead is scoped by a knot.yml program key, which is valid with no
    # patches row.
    Patch.find_by!(slug: "ganymede").then { |patch| ActiveRecord::Base.connection.execute("DELETE FROM patches WHERE id = #{patch.id}") }
    grant("patch_lead", "ganymede")
    grant("patch_viewer", "europa")

    expect(described_class.for(user.reload_roles!)).to eq("europa" => ["viewer"])
  end

  it "names only scopable roles of config/roles.yml" do
    described_class::NAMES.each_key do |key|
      expect(RoleRegistry.fetch(key)).to be_scopable
    end
  end
end
