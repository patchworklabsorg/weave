# frozen_string_literal: true

require "rails_helper"

# A superadmin approves a production console by entering the code it shows.
RSpec.describe "Admin console access", type: :request do
  let(:superadmin) { create(:user, :superadmin, :verified) }
  let!(:console_request) { ConsoleAccessRequest.open!(kind: "sql", host: "weave-web") }

  it "shows the request for a code, then approves it as the signed-in superadmin" do
    sign_in_via_magic_link(superadmin)

    post lookup_admin_console_access_path, params: { code: console_request.code }
    expect(response.body).to include("SQL console", "weave-web")

    post decide_admin_console_access_path, params: { code: console_request.code, decision: "approve" }

    expect(response).to redirect_to(admin_console_access_path)
    expect(console_request.reload).to have_attributes(status: "approved", decided_by: superadmin)
  end

  it "denies a request" do
    sign_in_via_magic_link(superadmin)

    post decide_admin_console_access_path, params: { code: console_request.code, decision: "deny" }

    expect(console_request.reload).to be_denied
  end

  it "rejects a wrong code" do
    sign_in_via_magic_link(superadmin)

    post decide_admin_console_access_path, params: { code: "0000-0000", decision: "approve" }

    expect(flash[:alert]).to include("No open console request")
    expect(console_request.reload).to be_pending
  end

  it "refuses an admin who is not a superadmin" do
    sign_in_via_magic_link(create(:user, :admin, :verified))

    post decide_admin_console_access_path, params: { code: console_request.code, decision: "approve" }

    expect(response).to redirect_to(admin_root_path)
    expect(console_request.reload).to be_pending
  end

  # Only members can be impersonated, so the admin routes are closed. The
  # controller also refuses impersonation, in case that rule changes.
  it "refuses an approval during impersonation" do
    sign_in_via_magic_link(create(:user, :owner, :verified))
    post impersonate_admin_user_path(create(:user, :verified))

    post decide_admin_console_access_path, params: { code: console_request.code, decision: "approve" }

    expect(console_request.reload).to be_pending
  end
end
