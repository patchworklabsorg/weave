# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Data takeout", type: :request do
  include ActiveJob::TestHelper

  let(:member) { create(:user, :verified) }

  it "needs a signed-in member" do
    get takeout_path

    expect(response).to redirect_to("/login")
  end

  it "asks for an export and lets the member download it" do
    sign_in_via_magic_link(member)

    post takeout_path
    expect(response).to redirect_to(takeout_path)
    perform_enqueued_jobs(only: BuildTakeoutJob)
    takeout = member.takeout_requests.sole

    get takeout_path
    expect(response.body).to include(download_takeout_path(takeout))

    get download_takeout_path(takeout)
    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include("attachment")
    expect(JSON.parse(response.body)["weave_id"]).to eq(member.p_id)
    expect(takeout.reload.downloaded_at).to be_present
  end

  it "does not let a member download another member's export" do
    other = create(:takeout_request, status: "ready", expires_at: 1.day.from_now)
    other.archive.attach(io: StringIO.new("{}"), filename: "x.json", content_type: "application/json")
    sign_in_via_magic_link(member)

    get download_takeout_path(other)

    expect(response).to redirect_to(takeout_path)
  end

  it "refuses the database id of the member's own export" do
    takeout = create(:takeout_request, user: member, status: "ready", expires_at: 1.day.from_now)
    takeout.archive.attach(io: StringIO.new("{}"), filename: "x.json", content_type: "application/json")
    sign_in_via_magic_link(member)

    get "/profile/export/#{takeout.id}/download"

    expect(response).to redirect_to(takeout_path)
    expect(takeout.reload.downloaded_at).to be_nil
  end

  it "refuses an expired export" do
    takeout = create(:takeout_request, user: member, status: "ready", expires_at: 1.minute.ago)
    takeout.archive.attach(io: StringIO.new("{}"), filename: "x.json", content_type: "application/json")
    sign_in_via_magic_link(member)

    get download_takeout_path(takeout)

    expect(response).to redirect_to(takeout_path)
  end

  context "when an admin impersonates the member" do
    it "refuses the export" do
      admin = create(:user, :admin, :verified)
      sign_in_via_magic_link(admin)
      post impersonate_admin_user_path(member)

      post takeout_path

      expect(member.takeout_requests).to be_empty
      expect(flash[:alert]).to include("impersonate")
    end
  end
end
