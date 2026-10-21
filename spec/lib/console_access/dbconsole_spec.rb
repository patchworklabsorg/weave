# frozen_string_literal: true

require "rails_helper"
# config/application.rb loads this only for `bin/rails dbconsole`.
require Rails.root.join("lib/console_access/dbconsole").to_s

RSpec.describe ConsoleAccess::Dbconsole do
  let(:adapter) { ActiveRecord::ConnectionAdapters::PostgreSQLAdapter }
  let(:db_config) { ActiveRecord::Base.configurations.find_db_config(Rails.env) }

  # The psql path sets PG* variables in ENV.
  around do |example|
    env = ENV.to_h
    example.run
  ensure
    ENV.replace(env)
  end

  it "opens the audited SQL console in a protected environment" do
    allow(ConsoleAccess).to receive(:protected_environment?).and_return(true)
    sql_console = instance_double(ConsoleAccess::SqlConsole)
    allow(ConsoleAccess::SqlConsole).to receive(:new).with(db_config:).and_return(sql_console)

    expect(sql_console).to receive(:start)
    expect(adapter).not_to receive(:find_cmd_and_exec)

    adapter.dbconsole(db_config)
  end

  it "keeps psql in other environments" do
    allow(ConsoleAccess).to receive(:protected_environment?).and_return(false)

    expect(adapter).to receive(:find_cmd_and_exec)

    adapter.dbconsole(db_config)
  end

  it "protects production and staging" do
    expect(ConsoleAccess.protected_environment?("production")).to be(true)
    expect(ConsoleAccess.protected_environment?("development")).to be(false)
  end
end
