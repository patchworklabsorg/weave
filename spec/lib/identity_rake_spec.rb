# frozen_string_literal: true

require "rails_helper"
require "rake"

# The one-time bootstrap of the identity team (lib/tasks/identity.rake).
RSpec.describe "identity rake tasks", type: :task do
  before(:all) do # rubocop:disable RSpec/BeforeAfterAll
    Rails.application.load_tasks unless Rake::Task.task_defined?("identity:bootstrap")
  end

  let(:owner) { create(:user, :owner, :verified) }
  let(:members) { create_list(:user, 3, :verified) }

  def run(task, env)
    env.each { |key, value| ENV[key] = value }
    Rake::Task[task].reenable
    Rake::Task[task].invoke
  ensure
    env.each_key { |key| ENV.delete(key) }
  end

  it "adds the first verifiers and prints the circle" do
    expect { run("identity:bootstrap", "BY" => owner.email, "MEMBERS" => members.map(&:email).join(",")) }
      .to output(/#{members.last.full_name} \(#{members.last.email}\) verifies #{members.first.full_name}/).to_stdout

    expect(members.map { |user| user.reload.identity_team }).to all(be(true))
  end

  it "refuses once a team member is verified" do
    create(:verification, :verified, user: create(:user, :identity_team))

    expect { run("identity:bootstrap", "BY" => owner.email, "MEMBERS" => members.map(&:email).join(",")) }
      .to raise_error(SystemExit).and output(/closed/).to_stderr
    expect(members.first.reload.identity_team).to be(false)
  end

  it "shows the bootstrap status" do
    IdentityGovernance.bootstrap!(members, by: owner)

    expect { run("identity:bootstrap_status", {}) }.to output(/planned verifier .*The bootstrap is closed/m).to_stdout
  end

  it "refuses after its first run" do
    IdentityGovernance.bootstrap!(members.first(2), by: owner)

    expect { run("identity:bootstrap", "BY" => owner.email, "MEMBERS" => members.map(&:email).join(",")) }
      .to raise_error(SystemExit).and output(/ran before/).to_stderr
    expect(members.last.reload.identity_team).to be(false)
  end
end
