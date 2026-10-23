# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConsoleAccess::SignIn do
  let(:output) { StringIO.new }
  let(:admin) { create(:user, :admin) }

  # The sleeper runs between polls, so it stands in for the person in Weave.
  def sign_in(&act)
    described_class.new(kind: "console", output:, host: "weave-web", sleeper: ->(_) { act.call(ConsoleAccessRequest.last) })
  end

  it "shows the code and the sign-in page, then returns the user" do
    user = sign_in { it.confirm!(by: admin) }.await!

    expect(user).to eq(admin)
    expect(output.string).to include("#{Weave.url}/admin/console_access")
    expect(output.string).to match(/[0-9A-Z]{4}-[0-9A-Z]{4}/)
  end

  it "stays closed when the user is no longer an admin" do
    expect do
      sign_in do |request|
        request.confirm!(by: admin)
        admin.update!(role: "user")
      end.await!
    end.to raise_error(ConsoleAccess::Error, /cannot be used/)
  end

  it "stops when the console is marked as not mine" do
    expect { sign_in { it.reject!(by: admin) }.await! }.to raise_error(ConsoleAccess::Error, /not yours/)
  end

  it "stops when the code expires" do
    expect { sign_in { travel(ConsoleAccessRequest::EXPIRATION + 1.second) }.await! }
      .to raise_error(ConsoleAccess::Error, /expired/)
  end
end
