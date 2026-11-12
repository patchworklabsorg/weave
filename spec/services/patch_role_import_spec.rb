# frozen_string_literal: true

require "rails_helper"

# Moving an app's roles to a patch: Krater's reviewer and admin become the
# Ganymede patch roles krater:reviewer and krater:admin.
RSpec.describe PatchRoleImport do
  let(:superadmin) { create(:user, :superadmin, :verified) }
  let(:krater) { Doorkeeper::Application.create!(name: "Krater", redirect_uri: "https://krater.example.com/cb") }
  let(:reviewer) { create(:user, :verified) }
  let(:reviewers) { create(:group, name: "Krater Reviewers", slug: "krater-reviewers") }
  let!(:admins) { create(:group, name: "Krater Admins", slug: "krater-admins") }

  before do
    krater.update!(patch: create(:patch, slug: "ganymede", name: "Project Ganymede"))
    review = ApplicationRole.create!(application: krater, key: "reviewer", name: "Reviewer", description: "Reviews proposals.")
    ApplicationRole.create!(application: krater, key: "admin", name: "Admin")
    ApplicationRoleAssignment.create!(role: review, assignee: reviewer)
    ApplicationRoleAssignment.create!(role: review, assignee: reviewers)
  end

  def ganymede = Patch.find_by!(slug: "ganymede")

  def import(apply: false, **options)
    described_class.call(application: krater, patch: ganymede, prefix: "krater", actor: superadmin,
                         group_map: { "krater-admins" => "admin" }, apply:, **options)
  end

  def app_role_rows = ApplicationRole.order(:id).map(&:attributes) + ApplicationRoleAssignment.order(:id).map(&:attributes)

  it "plans the roles and the assignments in a dry run, and writes nothing" do
    result = import

    expect(result.lines.first(2)).to eq(["App: Krater (client id #{krater.uid}). Patch: Project Ganymede (ganymede).",
                                         "Dry run. Nothing was written. Run again with APPLY=1 to write it."])
    expect(result.steps.map { |step| [step.status, step.text] }).to eq(
      [
        [:create, "role krater:admin on ganymede (Admin)"],
        [:grant, "krater:admin for group krater-admins (0 active members)"],
        [:create, "role krater:reviewer on ganymede (Reviewer)"],
        [:create, "krater:reviewer for user #{reviewer.email}"],
        [:create, "krater:reviewer for group krater-reviewers"]
      ]
    )
    expect(result.lines.last).to include("Only a superadmin can add members", "krater-admins, krater-reviewers")
    expect(PatchRole.count).to eq(0)
    expect(PatchRoleAssignment.count).to eq(0)
  end

  it "writes the roles and the assignments, and the claim has them" do # rubocop:disable RSpec/MultipleExpectations
    create(:group_membership, group: admins, user: create(:user, :verified, email: "admin@example.com"), added_by: superadmin)

    result = import(apply: true)

    expect(result.created).to eq(5)
    roles = ganymede.roles.order(:key)
    expect(roles.map { |role| [role.key, role.name, role.description, role.created_by] }).to eq(
      [["krater:admin", "Admin", nil, superadmin], ["krater:reviewer", "Reviewer", "Reviews proposals.", superadmin]]
    )
    expect(PatchRoleAssignment.all.map { |assignment| [assignment.role.key, assignment.assignee] })
      .to contain_exactly(["krater:admin", admins], ["krater:reviewer", reviewer], ["krater:reviewer", reviewers])
    expect(PatchRoleAssignment.distinct.pluck(:created_by_id)).to eq([superadmin.id])
    expect(PatchRole.first.versions.last.whodunnit).to eq(superadmin.id.to_s)
    expect(PatchRoles.for(reviewer)).to eq("ganymede" => ["krater:reviewer"])
    expect(PatchRoles.for(User.find_by!(email: "admin@example.com"))).to eq("ganymede" => ["krater:admin"])
  end

  it "creates nothing on a second run, and reports each item as already present" do
    import(apply: true)

    result = import(apply: true)

    expect(result.created).to eq(0)
    expect(result.steps.map(&:status)).to all(eq(:present))
    expect(PatchRole.count).to eq(2)
    expect(PatchRoleAssignment.count).to eq(3)
  end

  it "never changes the app roles or their assignments" do
    before = app_role_rows

    import(apply: true)

    expect(app_role_rows).to eq(before)
  end

  it "skips a system group, and reports it" do
    staff = create(:group, :system, name: "Staff (system)", slug: "staff-system")
    ApplicationRoleAssignment.create!(role: ApplicationRole.find_by!(key: "admin"), assignee: staff)

    result = import(apply: true, group_map: {})

    expect(result.steps).to include(PatchRoleImport::Step.new(status: :skip,
                                                              text: "krater:admin for group staff-system: a system group can't hold a patch role"))
    expect(PatchRoleAssignment.where(assignee: staff)).to be_empty
    expect(result.groups).to eq([reviewers])
  end

  it "refuses a system group in GROUP_MAP the same way" do
    create(:group, :system, name: "Everyone (system)", slug: "everyone-system")

    result = import(apply: true, group_map: { "everyone-system" => "admin" })

    expect(result.steps.map(&:status)).to include(:skip)
    expect(PatchRoleAssignment.where(assignee_type: "Group").map(&:assignee)).to eq([reviewers])
  end

  it "refuses an actor who is not a superadmin, an unknown app or patch, a bad prefix and a bad GROUP_MAP" do # rubocop:disable RSpec/MultipleExpectations
    admin = create(:user, :admin, :verified)
    base = { application: krater, patch: ganymede, prefix: "krater", actor: superadmin }

    expect { described_class.call(**base, actor: admin) }.to raise_error(described_class::Error, /superadmin/)
    expect { described_class.call(**base, actor: nil) }.to raise_error(described_class::Error, /superadmin/)
    expect { described_class.call(**base, application: nil) }.to raise_error(described_class::Error, /Unknown app/)
    expect { described_class.call(**base, patch: nil) }.to raise_error(described_class::Error, /Unknown patch/)
    expect { described_class.call(**base, prefix: "Krater:") }.to raise_error(described_class::Error, /prefix/)
    expect { described_class.call(**base, group_map: { "nope" => "admin" }) }.to raise_error(described_class::Error, /Unknown group nope/)
    expect { described_class.call(**base, group_map: { "krater-reviewers" => "owner" }) }
      .to raise_error(described_class::Error, /no role owner/)
    expect(PatchRole.count).to eq(0)
  end

  it "writes nothing when one item fails" do
    allow_any_instance_of(PatchRoleAssignment).to receive(:save!).and_raise(ActiveRecord::RecordInvalid) # rubocop:disable RSpec/AnyInstance

    expect { import(apply: true) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(PatchRole.count).to eq(0)
  end

  it "refuses an app that does not belong to the patch" do
    krater.update!(patch: nil)

    expect { import }.to raise_error(described_class::Error, /Krater does not belong to ganymede/)
    krater.update!(patch: create(:patch, slug: "europa"))
    expect { import(apply: true) }.to raise_error(described_class::Error, /does not belong/)
    expect(PatchRole.count).to eq(0)
  end

  it "reports a patch role with the same key and another name as a conflict, and refuses APPLY without MERGE" do
    ganymede.roles.create!(key: "krater:reviewer", name: "Reviewer (old)", description: "Reviews proposals.")

    expect(import.steps.map(&:status)).to include(:conflict)
    expect { import(apply: true) }.to raise_error(described_class::Error, /MERGE=1/)
    expect(PatchRoleAssignment.count).to eq(0)

    import(apply: true, merge: true)
    expect(ganymede.roles.find_by!(key: "krater:reviewer").name).to eq("Reviewer (old)")
    expect(PatchRoles.for(reviewer)).to eq("ganymede" => ["krater:reviewer"])
  end

  it "gives a GROUP_MAP group with no app role assignment the status grant, with its active member count" do
    create(:group_membership, group: admins, user: create(:user, :verified), added_by: superadmin)
    create(:group_membership, group: reviewers, user: create(:user, :verified), added_by: superadmin)

    steps = import(group_map: { "krater-admins" => "admin", "krater-reviewers" => "reviewer" }).steps

    expect(steps.select { |step| step.status == :grant }.map(&:text)).to eq(["krater:admin for group krater-admins (1 active members)"])
    expect(steps.map(&:text)).to include("krater:reviewer for group krater-reviewers")
  end

  it "skips an assignment that an admin removed before, unless RESTORE" do
    import(apply: true)
    PaperTrail.request(whodunnit: superadmin.id.to_s) { PatchRoleAssignment.find_by!(assignee: reviewer).destroy! }

    result = import(apply: true)

    expect(result.steps.map(&:label)).to include("previously removed")
    expect(PatchRoles.for(reviewer)).to eq({})

    import(apply: true, restore: true)
    expect(PatchRoles.for(reviewer)).to eq("ganymede" => ["krater:reviewer"])
  end

  it "checks each record in a dry run, and APPLY refuses an invalid item" do
    stub_const("PatchRoleImport::PREFIX_FORMAT", /.*/)

    result = described_class.call(application: krater, patch: ganymede, prefix: "Bad Prefix", actor: superadmin)

    expect(result.steps.map(&:status)).to all(eq(:invalid))
    expect(result.steps.first.text).to include("Key is invalid")
    expect { described_class.call(application: krater, patch: ganymede, prefix: "Bad Prefix", actor: superadmin, apply: true) }
      .to raise_error(described_class::Error, /invalid items/)
    expect(PatchRole.count).to eq(0)
  end
end
