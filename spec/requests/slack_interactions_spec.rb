# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Slack interactions webhook", type: :request do
  let(:secret) { "test_signing_secret" }

  before do
    allow_any_instance_of(Webhooks::SlackController)
      .to receive(:slack_signing_secret).and_return(secret)
  end

  def signed_post(body)
    ts = Time.now.to_i.to_s
    sig = "v0=" + OpenSSL::HMAC.hexdigest("SHA256", secret, "v0:#{ts}:#{body}")
    post "/webhooks/slack/interactions",
      params: body,
      headers: {
        "X-Slack-Signature" => sig,
        "X-Slack-Request-Timestamp" => ts,
        "CONTENT_TYPE" => "application/x-www-form-urlencoded"
      }
  end

  it "enqueues promotion and replaces the message when the CoC button is accepted" do
    payload = {
      type: "block_actions",
      user: { id: "U123" },
      actions: [{ action_id: "accept_coc", value: "U123" }]
    }.to_json

    expect { signed_post("payload=#{CGI.escape(payload)}") }
      .to have_enqueued_job(SlackCodeOfConductAcceptedJob).with("U123")

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["replace_original"]).to be(true)
  end

  it "ignores unrelated actions without enqueuing anything" do
    payload = { type: "block_actions", user: { id: "U9" }, actions: [{ action_id: "something_else" }] }.to_json

    expect { signed_post("payload=#{CGI.escape(payload)}") }
      .not_to have_enqueued_job(SlackCodeOfConductAcceptedJob)

    expect(response).to have_http_status(:ok)
  end

  it "rejects a request with an invalid signature" do
    post "/webhooks/slack/interactions",
      params: "payload=%7B%7D",
      headers: {
        "X-Slack-Signature" => "v0=deadbeef",
        "X-Slack-Request-Timestamp" => Time.now.to_i.to_s,
        "CONTENT_TYPE" => "application/x-www-form-urlencoded"
      }

    expect(response).to have_http_status(:unauthorized)
  end
end
