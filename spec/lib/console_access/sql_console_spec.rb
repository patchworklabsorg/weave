# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConsoleAccess::SqlConsole do
  let(:superadmin) { create(:user, :superadmin, first_name: "Grace", last_name: "Hopper") }
  let(:approval) { instance_double(ConsoleAccess::Approval, await!: superadmin) }
  let(:db_config) { ActiveRecord::Base.configurations.find_db_config(Rails.env) }
  let(:output) { StringIO.new }

  def run_console(*lines)
    answers = ["Check a stuck signup", *lines]
    input = ->(_prompt, single_line:) { answers.shift }
    described_class.new(db_config:, input:, output:, approval:).start
    Console1984::Session.last
  end

  it "records the approver, the reason and each statement in Console1984" do
    session = run_console("SELECT 1 AS one, 'x' AS two;", "\\q")

    expect(session.user.username).to eq("Grace Hopper (#{superadmin.p_id})")
    expect(session.reason).to eq("SQL (#{db_config.name}): Check a stuck signup")
    expect(session.commands.pluck(:statements)).to eq(["SELECT 1 AS one, 'x' AS two;"])
    expect(output.string).to include("one | two", "1   | x", "(1 row)")
  end

  it "writes out a backslash command as SQL in the record" do
    session = run_console("\\dt")

    expect(session.commands.sole.statements).to start_with("\\dt\nSELECT table_name FROM information_schema.tables")
    expect(output.string).to include("users")
  end

  it "records and refuses a statement on the audit tables" do
    session = run_console("DELETE FROM console1984_commands;")

    expect(session.commands.sole.statements).to eq("DELETE FROM console1984_commands;")
    expect(output.string).to include("Refused")
  end

  it "shows a SQL error and keeps going" do
    session = run_console("SELECT nope;", "SELECT 2 AS two;")

    expect(output.string).to include("column \"nope\" does not exist")
    expect(session.commands.pluck(:statements)).to eq(["SELECT nope;", "SELECT 2 AS two;"])
  end

  it "needs a reason" do
    input = ->(_prompt, single_line:) { "" }

    expect { described_class.new(db_config:, input:, output:, approval:).start }
      .not_to change(Console1984::Session, :count)
    expect(output.string).to include("A reason is required.")
  end
end
