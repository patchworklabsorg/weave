# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConsoleAccess::UsernameResolver do
  let(:superadmin) { create(:user, :superadmin, first_name: "Grace", last_name: "Hopper") }

  it "names the approver with the PWL id, for the Console1984 session" do
    approval = instance_double(ConsoleAccess::Approval, await!: superadmin)
    allow(ConsoleAccess::Approval).to receive(:new).with(kind: "console").and_return(approval)

    expect(described_class.new.current).to eq("Grace Hopper (#{superadmin.p_id})")
  end

  it "ends the console when the request is not approved" do
    approval = instance_double(ConsoleAccess::Approval)
    allow(approval).to receive(:await!).and_raise(ConsoleAccess::Error, "The console request was denied.")
    allow(ConsoleAccess::Approval).to receive(:new).and_return(approval)

    expect { described_class.new.current }.to raise_error(SystemExit).and output(/denied/).to_stderr
  end
end
