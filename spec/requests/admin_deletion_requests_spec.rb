# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin deletion requests", type: :request do
  include ActiveJob::TestHelper

  let(:reviewer) { create(:user, :identity_team) }
  let(:member) { create(:user, :verified) }
  let!(:deletion_request) { create(:deletion_request, user: member) }

  it "is for the identity team only" do
    sign_in_via_magic_link(create(:user, :admin, :verified))

    get admin_deletion_requests_path

    expect(response).to redirect_to(admin_root_path)
  end

  it "finds a request by its public id and not by its database id" do
    sign_in_via_magic_link(reviewer)

    expect(admin_deletion_request_path(deletion_request)).to eq("/admin/deletion_requests/#{deletion_request.hashid}")
    get "/admin/deletion_requests/#{deletion_request.id}"

    expect(response).to have_http_status(:not_found)
  end

  it "lists requests with their due date" do
    sign_in_via_magic_link(reviewer)

    get admin_deletion_requests_path

    expect(response.body).to include(deletion_request.public_id, deletion_request.review_due_at.to_date.to_fs(:long))
  end

  it "approves a request and runs the pipeline in a job" do
    sign_in_via_magic_link(reviewer)

    perform_enqueued_jobs(only: RunDeletionPipelineJob) do
      patch approve_admin_deletion_request_path(deletion_request), params: { review_note: "Reply from the address on file." }
    end

    expect(deletion_request.reload).to be_completed
    expect(User.exists?(member.id)).to be(false)

    get admin_deletion_request_path(deletion_request)
    expect(response.body).to include("fold_aggregates", "write_knot_record", "sever_identity", "send_receipt")
  end

  it "rejects a request with a reason" do
    sign_in_via_magic_link(reviewer)

    patch reject_admin_deletion_request_path(deletion_request), params: { review_note: "No reply." }

    expect(deletion_request.reload).to be_rejected
    expect(User.exists?(member.id)).to be(true)
  end

  it "shows the departed totals with suppression" do
    sign_in_via_magic_link(reviewer)
    DeleteTimeAggregates.add!(DeleteTimeAggregates::Bands.new(program: "ganymede", year: 2026, outcome: "granted",
                                                              age_band: "16-17", region: "US", amount_band: "none"))

    get admin_delete_time_aggregates_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ganymede-2026", "hidden")
  end
end
