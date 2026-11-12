# frozen_string_literal: true

require "rails_helper"
require "rake"

# The patch tasks (lib/tasks/patches.rake).
RSpec.describe "patches rake tasks", type: :task do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    Rails.application.load_tasks unless Rake::Task.task_defined?("patches:import_app_roles")
  end

  let(:superadmin) { create(:user, :superadmin, :verified) }
  let(:krater) { Doorkeeper::Application.create!(name: "Krater", redirect_uri: "https://krater.example.com/cb") }

  before do
    create(:patch, slug: "ganymede", name: "Project Ganymede")
    role = ApplicationRole.create!(application: krater, key: "reviewer", name: "Reviewer")
    ApplicationRoleAssignment.create!(role:, assignee: create(:group, name: "Krater Admins", slug: "krater-admins"))
  end

  def run(env)
    env.each { |key, value| ENV[key] = value }
    Rake::Task["patches:import_app_roles"].reenable
    Rake::Task["patches:import_app_roles"].invoke
  ensure
    env.each_key { |key| ENV.delete(key) }
  end

  def env(**extra) = { "APP" => krater.public_id, "PATCH" => "ganymede", "PREFIX" => "krater", "ACTOR" => superadmin.email, **extra }

  it "prints the plan and writes nothing without APPLY=1" do
    expect { run(env) }.to output(/Dry run.*create  role krater:reviewer.*Warning.*krater-admins/m).to_stdout
    expect(PatchRole.count).to eq(0)
  end

  it "writes with APPLY=1, and finds the app by its client id too" do
    expect { run(env("APP" => krater.uid, "APPLY" => "1")) }.to output(/Applied/).to_stdout
    expect(PatchRole.pluck(:key)).to eq(["krater:reviewer"])
  end

  it "stops with a message for an actor who is not a superadmin, and for a bad GROUP_MAP" do
    admin = create(:user, :admin, :verified)

    expect { run(env("ACTOR" => admin.email, "APPLY" => "1")) }.to raise_error(SystemExit).and output(/superadmin/).to_stderr
    expect { run(env("GROUP_MAP" => "krater-admins")) }.to raise_error(SystemExit).and output(/slug:role_key/).to_stderr
    expect(PatchRole.count).to eq(0)
  end
end
