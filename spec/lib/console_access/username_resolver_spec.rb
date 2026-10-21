# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConsoleAccess::UsernameResolver do
  let(:superadmin) { create(:user, :superadmin, first_name: "Grace", last_name: "Hopper") }

  # bin/rails console defines Rails::Console. The spec process does not.
  before { stub_const("Rails::Console", Class.new) }

  it "names the approver with the PWL id, for the Console1984 session" do
    approval = instance_double(ConsoleAccess::Approval, await!: superadmin)
    allow(ConsoleAccess::Approval).to receive(:new).with(kind: "console").and_return(approval)

    expect(described_class.new.current).to eq("Grace Hopper (#{superadmin.p_id})")
  end

  it "asks for one approval per console" do
    approval = instance_double(ConsoleAccess::Approval, await!: superadmin)
    resolver = described_class.new

    expect(ConsoleAccess::Approval).to receive(:new).once.and_return(approval)

    2.times { resolver.current }
  end

  it "does not wait for an approval outside a console" do
    hide_const("Rails::Console")

    expect(ConsoleAccess::Approval).not_to receive(:new)

    expect(described_class.new.current).to be_nil
  end

  it "ends the console when the request is not approved" do
    approval = instance_double(ConsoleAccess::Approval)
    allow(approval).to receive(:await!).and_raise(ConsoleAccess::Error, "The console request was denied.")
    allow(ConsoleAccess::Approval).to receive(:new).and_return(approval)

    expect { described_class.new.current }.to raise_error(SystemExit).and output(/denied/).to_stderr
  end
end
