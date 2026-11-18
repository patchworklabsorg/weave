# frozen_string_literal: true

require "rails_helper"

# Each API call writes a usage row (Service::Key::Usage). The row keeps the
# request headers for debugging, without credentials and without anything
# that is not an HTTP header.
RSpec.describe "API usage log", type: :request do
  let(:member) { create(:user, :verified) }
  let(:service) { create(:service, name: "Krater") }
  let(:key) { create(:service_key, service:) }

  def call_api
    post api_v1_thread_count_project_events_path,
         params: { sub: member.p_id, project_ref: "krater-42", outcome: "approved", reason: "Shipped" }.to_json,
         headers: { "X-Api-Key" => key.api_key, "Content-Type" => "application/json", "Accept" => "application/json",
                    "Authorization" => "Bearer some-bearer-token", "Cookie" => "session=abc123",
                    "Cf-Access-Jwt-Assertion" => "proxy-jwt-value", "Proxy-Authorization" => "Basic cHJveHk=",
                    "X-Auth-Token" => "other-token-value"
}
  end

  def usage = Service::Key::Usage.order(:id).last

  it "records the response code and the duration" do
    call_api

    expect(response).to have_http_status(:created)
    expect(usage).to have_attributes(response_code: 201, duration_ms: be_a(Integer))
  end

  it "keeps the HTTP request headers, without the credentials" do
    call_api
    headers = JSON.parse(usage.request_headers)

    expect(headers).to include("HTTP_ACCEPT" => "application/json")
    expect(headers.keys).not_to include("HTTP_AUTHORIZATION", "HTTP_COOKIE", "HTTP_X_API_KEY")
    expect(usage.request_headers).not_to include(key.api_key, "some-bearer-token", "abc123")
  end

  it "drops a credential header that is not in the fixed list" do
    call_api

    expect(usage.request_headers).not_to include("proxy-jwt-value", "cHJveHk=", "other-token-value")
  end

  it "stores nothing from the Rack env that is not an HTTP header" do
    call_api
    headers = JSON.parse(usage.request_headers)

    expect(headers.keys).to all(match(/\A(HTTP_|CONTENT_TYPE\z|CONTENT_LENGTH\z)/))
    expect(usage.request_headers).not_to include(Rails.application.secret_key_base)
  end
end
