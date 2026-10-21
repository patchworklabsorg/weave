# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConsoleAccessMailer do
  it "tells the approver which console opened under their name" do
    superadmin = create(:user, :superadmin, first_name: "Grace", last_name: "Hopper")
    console_request = ConsoleAccessRequest.open!(kind: "sql", host: "weave-web")
    console_request.approve!(by: superadmin, ip: "203.0.113.7")

    mail = described_class.opened(console_request)

    expect(mail.to).to eq([superadmin.email])
    expect(mail.subject).to include("SQL console opened under your name")
    expect(mail.text_part.body.to_s).to include(superadmin.p_id, "weave-web", "203.0.113.7", "#{Weave.url}/admin/console")
  end
end
