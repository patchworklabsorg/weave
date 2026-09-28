# frozen_string_literal: true

require "rails_helper"

# The events endpoint creates users and changes their email addresses, so it
# must only act on requests Slack signed. It used to accept anything: the
# signature check was declared for :events in a concern and then silently
# replaced by the controller's own declaration for :interactions (Rails keeps
# only the last before_action per method).
RSpec.describe "Slack events webhook", type: :request do
  include ActiveJob::TestHelper

  let(:secret) { "test_signing_secret" }

  let(:team_join) do
    {
      type: "event_callback",
      event_id: "Ev#{SecureRandom.hex(4)}",
      event: { type: "team_join", user: { id: "U123", profile: { email: "someone@example.com" } } }
    }.to_json
  end

  before do
    allow_any_instance_of(Webhooks::SlackController) # rubocop:disable RSpec/AnyInstance
      .to receive(:slack_signing_secret).and_return(secret)
  end

  def post_event(body, timestamp: Time.now.to_i.to_s, signature: nil)
    signature ||= "v0=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "v0:#{timestamp}:#{body}")}"
    post "/webhooks/slack/events",
         params: body,
         headers: {
           "X-Slack-Signature"         => signature,
           "X-Slack-Request-Timestamp" => timestamp,
           "CONTENT_TYPE"              => "application/json"
         }
  end

  it "processes a correctly signed event" do
    expect { post_event(team_join) }.to have_enqueued_job(SlackWebhookEventJob)

    expect(response).to have_http_status(:ok)
  end

  it "answers Slack's signed URL verification handshake" do
    post_event({ type: "url_verification", challenge: "abc123" }.to_json)

    expect(response.parsed_body).to eq("challenge" => "abc123")
  end

  it "rejects an unsigned event without processing it" do
    expect do
      post "/webhooks/slack/events", params: team_join, headers: { "CONTENT_TYPE" => "application/json" }
    end.not_to have_enqueued_job(SlackWebhookEventJob)

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects an event with a forged signature" do
    expect { post_event(team_join, signature: "v0=deadbeef") }.not_to have_enqueued_job(SlackWebhookEventJob)

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a replayed event" do
    stale = 10.minutes.ago.to_i.to_s

    expect { post_event(team_join, timestamp: stale) }.not_to have_enqueued_job(SlackWebhookEventJob)

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a timestamp from the future" do
    future = 10.minutes.from_now.to_i.to_s

    expect { post_event(team_join, timestamp: future) }.not_to have_enqueued_job(SlackWebhookEventJob)

    expect(response).to have_http_status(:unauthorized)
  end

  # The attack this closes: a forged user_change pointed the victim's email at
  # an address the attacker reads, and a magic link requested for that address
  # then signed the attacker in as the victim.
  it "doesn't let a forged user_change event redirect someone's email" do
    victim = create(:user, :owner, :verified, slack_id: "UVICTIM01")
    forged = {
      type: "event_callback",
      event_id: "Ev#{SecureRandom.hex(4)}",
      event: { type: "user_change", user: { id: "UVICTIM01", profile: { email: "attacker@example.net" } } }
    }.to_json

    perform_enqueued_jobs do
      post "/webhooks/slack/events", params: forged, headers: { "CONTENT_TYPE" => "application/json" }
    end

    expect(victim.reload.email).not_to eq("attacker@example.net")
    expect(User.find_for_any_email("attacker@example.net")).to be_nil
  end
end
