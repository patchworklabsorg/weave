# frozen_string_literal: true

require "rails_helper"

# Patches in the admin panel. Any admin may look; only a superadmin may create
# a patch or change it. The slug never changes, and there is no delete.
RSpec.describe "Admin patches", type: :request do
  let(:admin) { create(:user, :admin, :verified) }
  let(:superadmin) { create(:user, :superadmin, :verified) }
  let(:owner) { create(:user, :owner, :verified) }
  let!(:ganymede) { create(:patch, slug: "ganymede", name: "Project Ganymede", description: "Space grants.") }

  it "is only for admins" do
    sign_in_via_magic_link(create(:user, :verified))

    get admin_patches_path
    expect(response).to redirect_to(login_path)

    get admin_patch_path(ganymede)
    expect(response).to redirect_to(login_path)
  end

  context "when signed in as a plain admin" do
    before { sign_in_via_magic_link(admin) }

    it "lists and shows patches, with the leads, the roles and their holders, and the linked apps, with no N+1" do # rubocop:disable RSpec/ExampleLength
      krater = Doorkeeper::Application.create!(name: "Krater", redirect_uri: "https://krater.example.com/cb", patch: ganymede)
      Doorkeeper::Application.create!(name: "Stash", redirect_uri: "https://stash.example.com/cb")
      leads = create_list(:user, 2, :verified, :patch_lead)
      viewers = create_list(:user, 2, :verified)
      %w[viewer reviewer].each do |key|
        role = ganymede.roles.create!(key:, name: key.titleize)
        viewers.each { |viewer| PatchRoleAssignment.create!(role:, assignee: viewer) }
        PatchRoleAssignment.create!(role:, assignee: create(:group, name: "#{key.titleize} group"))
      end

      get admin_patches_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Project Ganymede", "ganymede", "Space grants.")
      expect(response.body).not_to include("New patch")

      get admin_patch_path(ganymede)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Project Ganymede", krater.name, "Patch leads", leads.first.full_name, "Reviewer",
                                       "viewer", viewers.first.full_name, "Viewer group")
      expect(response.body).not_to include("Stash", edit_admin_patch_path(ganymede), "Add role", "Delete role")
    end

    it "can't create or edit a patch" do
      get new_admin_patch_path
      expect(response).to redirect_to(admin_patches_path)

      post admin_patches_path, params: { patch: { name: "Europa", slug: "europa" } }
      expect(response).to redirect_to(admin_patches_path)
      expect(Patch.exists?(slug: "europa")).to be(false)

      patch admin_patch_path(ganymede), params: { patch: { name: "Renamed" } }
      expect(ganymede.reload.name).to eq("Project Ganymede")
    end
  end

  context "when signed in as a superadmin" do
    before { sign_in_via_magic_link(superadmin) }

    it "creates a patch" do
      get new_admin_patch_path
      expect(response).to have_http_status(:ok)

      post admin_patches_path, params: { patch: { name: "Europa", slug: "europa", description: "Ocean grants." } }

      europa = Patch.find_by!(slug: "europa")
      expect(europa).to have_attributes(name: "Europa", description: "Ocean grants.", created_by: superadmin)
      expect(response).to redirect_to(admin_patch_path(europa))
      expect(europa.versions.last.whodunnit).to eq(superadmin.id.to_s)
    end

    it "shows the form again when the input is not valid" do
      post admin_patches_path, params: { patch: { name: "Europa", slug: "Not A Slug" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(Patch.exists?(name: "Europa")).to be(false)
    end

    it "changes the name and the description, never the slug" do
      get edit_admin_patch_path(ganymede)
      expect(response).to have_http_status(:ok)

      patch admin_patch_path(ganymede), params: { patch: { name: "Ganymede", description: "", slug: "europa" } }

      expect(ganymede.reload).to have_attributes(name: "Ganymede", description: "", slug: "ganymede")
      expect(response).to redirect_to(admin_patch_path(ganymede))
    end
  end
end
