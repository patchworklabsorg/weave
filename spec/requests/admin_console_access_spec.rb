# frozen_string_literal: true

require "rails_helper"

# The person at a production console enters its code to sign it in as
# themselves.
RSpec.describe "Admin console sign-in", type: :request do
  let(:admin) { create(:user, :admin, :verified) }
  let!(:console_request) { ConsoleAccessRequest.open!(kind: "sql", host: "weave-web") }

  it "submits the code without Turbo, because the lookup renders a page" do
    sign_in_via_magic_link(admin)

    get admin_console_access_path

    form = Nokogiri::HTML(response.body).at_css("form[action='#{lookup_admin_console_access_path}']")
    expect(form["data-turbo"]).to eq("false")
  end

  it "shows the console for a code, then records it under the signed-in admin" do
    sign_in_via_magic_link(admin)

    post lookup_admin_console_access_path, params: { code: console_request.code }
    expect(response.body).to include("SQL console", "weave-web")

    post confirm_admin_console_access_path, params: { code: console_request.code, answer: "mine" }

    expect(response).to redirect_to(admin_console_access_path)
    expect(console_request.reload).to have_attributes(status: "confirmed", user: admin, confirmed_ip: "127.0.0.1")
  end

  it "stops a console that is not mine" do
    sign_in_via_magic_link(admin)

    post confirm_admin_console_access_path, params: { code: console_request.code, answer: "not_mine" }

    expect(console_request.reload).to be_rejected
  end

  it "rejects a wrong code" do
    sign_in_via_magic_link(admin)

    post confirm_admin_console_access_path, params: { code: "0000-0000", answer: "mine" }

    expect(flash[:alert]).to include("No open console")
    expect(console_request.reload).to be_pending
  end

  it "is closed to members who are not admins" do
    sign_in_via_magic_link(create(:user, :verified))

    post confirm_admin_console_access_path, params: { code: console_request.code, answer: "mine" }

    expect(console_request.reload).to be_pending
  end

  # Only members can be impersonated, so the admin routes are closed. The
  # controller also refuses impersonation, in case that rule changes.
  it "refuses a sign-in during impersonation" do
    sign_in_via_magic_link(create(:user, :owner, :verified))
    post impersonate_admin_user_path(create(:user, :verified))

    post confirm_admin_console_access_path, params: { code: console_request.code, answer: "mine" }

    expect(console_request.reload).to be_pending
  end
end
