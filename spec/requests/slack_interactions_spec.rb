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
    sig = "v0=#{OpenSSL::HMAC.hexdigest("SHA256", secret, "v0:#{ts}:#{body}")}"
    post "/webhooks/slack/interactions",
         params: body,
         headers: {
           "X-Slack-Signature"         => sig,
           "X-Slack-Request-Timestamp" => ts,
           "CONTENT_TYPE"              => "application/x-www-form-urlencoded"
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

  it "thanks a full member without promising new access" do
    create(:user, slack_id: "U123", slack_membership: "member")
    payload = { type: "block_actions", user: { id: "U123" }, actions: [{ action_id: "accept_coc", value: "U123" }] }.to_json

    signed_post("payload=#{CGI.escape(payload)}")

    expect(response.parsed_body["text"]).not_to include("full access")
  end

  describe "code-of-conduct form" do
    let(:slack) { instance_double(SlackService) }
    let!(:user) { create(:user, slack_id: "U123", slack_membership: "member", first_name: "NOTSET", last_name: "NOTSET") }

    before { allow(SlackService).to receive(:new).and_return(slack) }

    def submission(first_name:, last_name:, user_id: "U123", accept: true)
      {
        type: "view_submission",
        user: { id: user_id },
        view: {
          callback_id: "coc_form",
          private_metadata: { channel: "D1", ts: "1.2" }.to_json,
          state: {
            values: {
              accept: { value: { selected_options: accept ? [{ value: "accept" }] : [] } },
              first_name: { value: { value: first_name } },
              last_name: { value: { value: last_name } }
            }
          }
        }
      }.to_json
    end

    it "opens the form from the DM button" do
      expect(slack).to receive(:open_code_of_conduct_form)
        .with(trigger_id: "T1", user: user, message: { channel: "D1", ts: "1.2" })
      payload = {
        type: "block_actions", trigger_id: "T1", user: { id: "U123" },
        container: { channel_id: "D1", message_ts: "1.2" },
        actions: [{ action_id: "open_coc_form", value: "U123" }]
      }.to_json

      signed_post("payload=#{CGI.escape(payload)}")

      expect(response).to have_http_status(:ok)
    end

    it "saves the name and accepts on submission" do
      expect { signed_post("payload=#{CGI.escape(submission(first_name: "Ada", last_name: "Lovelace"))}") }
        .to have_enqueued_job(SlackCodeOfConductAcceptedJob).with("U123", message: { channel: "D1", ts: "1.2" })

      expect(response.parsed_body["response_action"]).to eq("clear")
      user.reload
      expect(user.full_name).to eq("Ada Lovelace")
      expect(user.slack_coc_accepted_at).to be_present
    end

    it "shows an error next to a missing name" do
      signed_post("payload=#{CGI.escape(submission(first_name: "Ada", last_name: ""))}")

      expect(response.parsed_body).to eq("response_action" => "errors", "errors" => { "last_name" => "Enter your last name." })
      expect(user.reload.slack_coc_accepted_at).to be_nil
    end

    it "does not accept without the box checked" do
      signed_post("payload=#{CGI.escape(submission(first_name: "Ada", last_name: "Lovelace", accept: false))}")

      expect(response.parsed_body["errors"]).to have_key("accept")
      expect(user.reload.slack_coc_accepted_at).to be_nil
    end

    it "uses the submitting user, so nobody can accept for someone else" do
      other = create(:user, slack_id: "U999", slack_membership: "member", first_name: "Bo", last_name: "Bell")

      signed_post("payload=#{CGI.escape(submission(first_name: "Ada", last_name: "Lovelace", user_id: "U999"))}")

      expect(other.reload.slack_coc_accepted_at).to be_present
      expect(user.reload.slack_coc_accepted_at).to be_nil
    end
  end

  it "rejects a request with an invalid signature" do
    post "/webhooks/slack/interactions",
         params: "payload=%7B%7D",
         headers: {
           "X-Slack-Signature"         => "v0=deadbeef",
           "X-Slack-Request-Timestamp" => Time.now.to_i.to_s,
           "CONTENT_TYPE"              => "application/x-www-form-urlencoded"
         }

    expect(response).to have_http_status(:unauthorized)
  end
end
