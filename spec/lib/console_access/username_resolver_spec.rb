# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConsoleAccess::UsernameResolver do
  let(:admin) { create(:user, :admin, first_name: "Grace", last_name: "Hopper") }

  # bin/rails console defines Rails::Console. The spec process does not.
  before { stub_const("Rails::Console", Class.new) }

  it "names the person with the PWL id, for the Console1984 session" do
    sign_in = instance_double(ConsoleAccess::SignIn, await!: admin)
    allow(ConsoleAccess::SignIn).to receive(:new).with(kind: "console").and_return(sign_in)

    expect(described_class.new.current).to eq("Grace Hopper (#{admin.p_id})")
  end

  it "keeps the signed-in person for PaperTrail" do
    sign_in = instance_double(ConsoleAccess::SignIn, await!: admin)
    allow(ConsoleAccess::SignIn).to receive(:new).and_return(sign_in)
    resolver = described_class.new

    resolver.current

    expect(resolver.user).to eq(admin)
  end

  it "asks for one sign-in per console" do
    sign_in = instance_double(ConsoleAccess::SignIn, await!: admin)
    resolver = described_class.new

    expect(ConsoleAccess::SignIn).to receive(:new).once.and_return(sign_in)

    2.times { resolver.current }
  end

  it "does not wait for a sign-in outside a console" do
    hide_const("Rails::Console")

    expect(ConsoleAccess::SignIn).not_to receive(:new)

    expect(described_class.new.current).to be_nil
  end

  it "ends the console when the request is not signed in" do
    sign_in = instance_double(ConsoleAccess::SignIn)
    allow(sign_in).to receive(:await!).and_raise(ConsoleAccess::Error, "The console was marked as not yours.")
    allow(ConsoleAccess::SignIn).to receive(:new).and_return(sign_in)

    expect { described_class.new.current }.to raise_error(SystemExit).and output(/not yours/).to_stderr
  end
end
