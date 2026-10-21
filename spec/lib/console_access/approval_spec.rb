# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConsoleAccess::Approval do
  let(:output) { StringIO.new }
  let(:superadmin) { create(:user, :superadmin) }

  # The sleeper runs between polls, so it stands in for the superadmin.
  def approval(&decide)
    described_class.new(kind: "console", output:, host: "weave-web", sleeper: ->(_) { decide.call(ConsoleAccessRequest.last) })
  end

  it "shows the code and the approval page, then returns the approver" do
    approver = nil
    expect { approver = approval { it.approve!(by: superadmin) }.await! }
      .to have_enqueued_mail(ConsoleAccessMailer, :opened)

    expect(approver).to eq(superadmin)
    expect(output.string).to include("#{Weave.url}/admin/console_access")
    expect(output.string).to match(/[0-9A-Z]{4}-[0-9A-Z]{4}/)
  end

  it "stops when the request is denied" do
    expect { approval { it.deny!(by: superadmin) }.await! }.to raise_error(ConsoleAccess::Error, /denied/)
  end

  it "stops when the request expires" do
    expect { approval { travel(ConsoleAccessRequest::EXPIRATION + 1.second) }.await! }
      .to raise_error(ConsoleAccess::Error, /expired/)
  end
end
