# frozen_string_literal: true

require "rails_helper"

RSpec.describe DeletionReview do
  include ActiveJob::TestHelper

  let(:member) { create(:user, :verified) }
  let(:reviewer) { create(:user, :identity_team) }

  around { |example| travel_to(Time.zone.local(2026, 10, 12, 12)) { example.run } }

  it "makes a request with the review due date and the completion date from config" do
    create(:user, :identity_lead)

    result = described_class.request!(member)

    request = result.request
    expect(request.review_due_at).to eq(Time.zone.local(2026, 10, 26, 12))
    expect(request.complete_by).to eq(Time.zone.local(2026, 11, 11, 12))
    expect(request.receipt_email).to eq(member.email)
    expect(enqueued_jobs.map { |job| job["arguments"][1] }).to include("deletion_requested", "review_needed")
  end

  it "allows one open request per member" do
    described_class.request!(member)

    expect(described_class.request!(member)).not_to be_success
  end

  it "runs the pipeline only after a human approves with a note" do
    request = described_class.request!(member).request

    expect(described_class.approve(request, by: reviewer, note: "")).not_to be_success
    expect(RunDeletionPipelineJob).not_to have_been_enqueued

    result = described_class.approve(request, by: reviewer, note: "Reply from the address on file.")

    expect(result).to be_success
    expect(request.reload).to be_approved
    expect(request.reviewed_by).to eq(reviewer)
    expect(RunDeletionPipelineJob).to have_been_enqueued.with(request.id)
  end

  it "refuses a reviewer who is not on the identity team, the member, or below the member's level" do
    request = described_class.request!(member).request

    expect(described_class.approve(request, by: create(:user, :admin), note: "ok")).not_to be_success

    own = described_class.request!(reviewer).request
    expect(described_class.approve(own, by: reviewer, note: "ok")).not_to be_success

    superior = create(:user, :superadmin)
    above = described_class.request!(superior).request
    expect(described_class.approve(above, by: reviewer, note: "ok")).not_to be_success
  end

  it "rejects with a reason and tells the member" do
    request = described_class.request!(member).request

    result = described_class.reject(request, by: reviewer, note: "No reply from the address on file.")

    expect(result).to be_success
    expect(request.reload).to be_rejected
    expect(enqueued_jobs.map { |job| job["arguments"][1] }).to include("deletion_rejected")
  end

  it "lets the member cancel while the request waits" do
    request = described_class.request!(member).request

    expect(described_class.cancel!(request)).to be(true)
    expect(request.reload).to be_cancelled
  end

  it "runs a failed request again" do
    request = create(:deletion_request, user: member, status: "failed")

    expect(described_class.retry!(request, by: reviewer)).to be(true)
    expect(RunDeletionPipelineJob).to have_been_enqueued.with(request.id)
  end
end
