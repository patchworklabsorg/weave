# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account deletion requests", type: :request do
  let(:member) { create(:user, :verified) }

  before { sign_in_via_magic_link(member) }

  it "shows what happens to each category and the review time" do
    get deletion_request_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(*DataCategories.all.map { |category| CGI.escapeHTML(category.name) })
    expect(response.body).to include("14 days", "30 days")
  end

  it "needs the box ticked and the word typed" do
    post deletion_request_path, params: { understand: "1", confirmation: "nope" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(DeletionRequest.count).to eq(0)
  end

  it "makes a request that waits for the human review, with a visible due date" do
    post deletion_request_path, params: { understand: "1", confirmation: "delete" }

    expect(response).to redirect_to(deletion_request_path)
    request = member.deletion_requests.sole
    expect(request).to be_pending_review
    expect(User.exists?(member.id)).to be(true)

    get deletion_request_path
    expect(response.body).to include(request.review_due_at.to_date.to_fs(:long))
  end

  it "lets the member cancel while the request waits" do
    post deletion_request_path, params: { understand: "1", confirmation: "DELETE" }

    delete deletion_request_path

    expect(member.deletion_requests.sole).to be_cancelled
  end
end
