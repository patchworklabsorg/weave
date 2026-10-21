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
      .to change(ActionMailer::Base.deliveries, :count).by(1)

    expect(approver).to eq(superadmin)
    expect(ActionMailer::Base.deliveries.last.to).to eq([superadmin.email])
    expect(output.string).to include("#{Weave.url}/admin/console_access")
    expect(output.string).to match(/[0-9A-Z]{4}-[0-9A-Z]{4}/)
  end

  it "stays closed when the approval email cannot be sent" do
    allow(ConsoleAccessMailer).to receive(:opened).and_raise(StandardError, "SMTP is down")

    expect { approval { it.approve!(by: superadmin) }.await! }.to raise_error(ConsoleAccess::Error, /could not send/)
  end

  it "stays closed when the approver is no longer a superadmin" do
    request_approver = superadmin
    expect do
      approval do |request|
        request.approve!(by: request_approver)
        request_approver.update!(role: "admin")
      end.await!
    end.to raise_error(ConsoleAccess::Error, /cannot be used/)
  end

  it "stops when the request is denied" do
    expect { approval { it.deny!(by: superadmin) }.await! }.to raise_error(ConsoleAccess::Error, /denied/)
  end

  it "stops when the request expires" do
    expect { approval { travel(ConsoleAccessRequest::EXPIRATION + 1.second) }.await! }
      .to raise_error(ConsoleAccess::Error, /expired/)
  end
end
