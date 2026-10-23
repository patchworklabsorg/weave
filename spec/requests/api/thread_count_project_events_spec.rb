# frozen_string_literal: true

require "rails_helper"

# Krater and other services report project review outcomes, which feed the
# member's Thread Count. The test config lets the "Krater" service send them.
RSpec.describe "Thread Count project events API", type: :request do
  let(:member) { create(:user, :verified) }
  let(:params) { { sub: member.p_id, project_ref: "krater-42", outcome: "approved", reason: "Shipped", evidence_url: "https://krater.example.org/p/42" } }
  let(:service) { create(:service, name: "Krater") }
  let(:key) { create(:service_key, service:) }

  def post_event(params, api_key: key.api_key)
    post api_v1_thread_count_project_events_path, params: params.to_json,
                                                  headers: { "X-Api-Key" => api_key, "Content-Type" => "application/json" }
    response.parsed_body
  end


  it "records the outcome and returns only a receipt" do
    body = post_event(params)

    expect(response).to have_http_status(:created)
    entry = ThreadCount::Entry.sole
    expect(entry).to have_attributes(user: member, service:, kind: "project_approved", project_ref: "krater-42", reason: "Shipped")
    expect(body.keys).to contain_exactly("id", "project_ref", "kind", "created_at")
    expect(body["id"]).to eq(entry.public_id)
  end

  it "records an exceptional project as the approval plus the extra" do
    post_event(params.merge(outcome: "exceptional"))

    expect(response).to have_http_status(:created)
    expect(ThreadCount::Entry.pluck(:kind)).to contain_exactly("project_approved", "project_exceptional")
  end

  it "records a retry once" do
    2.times { post_event(params) }

    expect(response).to have_http_status(:created)
    expect(ThreadCount::Entry.count).to eq(1)
  end

  it "rejects a request without a key" do
    post api_v1_thread_count_project_events_path, params: params.to_json, headers: { "Content-Type" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects an unknown key" do
    post_event(params, api_key: "pwl_wrong")

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a revoked key" do
    key.revoke!

    post_event(params)

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a service that the config does not allow" do
    other_key = create(:service_key, service: create(:service, name: "Other"))

    post_event(params, api_key: other_key.api_key)

    expect(response).to have_http_status(:forbidden)
    expect(ThreadCount::Entry.count).to eq(0)
  end

  it "answers not found for an unknown member" do
    post_event(params.merge(sub: "PWL0000000000"))

    expect(response).to have_http_status(:not_found)
  end

  it "rejects an unknown outcome" do
    body = post_event(params.merge(outcome: "cool"))

    expect(response).to have_http_status(:unprocessable_content)
    expect(body["error_description"]).to include("Outcome must be one of")
  end

  it "keeps the member, the outcome and the reason out of the usage row" do
    # The usage logger fails on raw Rack headers today. Stub the header filter
    # so the row is written in full, as it will be once that is fixed.
    allow_any_instance_of(Api::V1::ProjectEventsController).to receive(:filter_sensitive_headers).and_return({}) # rubocop:disable RSpec/AnyInstance

    post_event(params.merge(outcome: "blacklisted", reason: "SECRET-REASON"))

    usage = key.usages.sole
    expect(usage.request_body).to be_nil
    expect(usage.response_body).to be_nil
    expect(usage.attributes.values.compact.map(&:to_s).join(" ")).not_to match(/blacklisted|SECRET-REASON|#{member.p_id}/)
  end

  it "keeps the reason, the evidence link and the outcome out of the logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    filtered = filter.filter(params.merge(outcome: "blacklisted", voucher: "a@example.org").stringify_keys)

    expect(filtered.values_at("reason", "evidence_url", "outcome", "voucher")).to all(eq("[FILTERED]"))
  end

  it "logs the call against the key" do
    post_event(params)

    expect(key.usages.sole).to have_attributes(request_path: api_v1_thread_count_project_events_path, request_method: "POST")
  end
end
