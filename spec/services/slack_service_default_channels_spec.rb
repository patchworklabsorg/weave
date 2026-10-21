# frozen_string_literal: true

require "rails_helper"

RSpec.describe SlackService do
  let(:service) { described_class.new }
  let(:invited) { [] }

  describe "#add_to_channels" do
    before do
      allow(service).to receive_messages(browser_token: "xoxc-test", slack_cookie: "xoxd-test", team_id: "T123",
                                         workspace_subdomain: "patchworklabs", member_channels: %w[C1 C2 C3])
    end

    # Answers each conversations.invite with the response for its channel. A
    # String is sent as the raw body.
    def stub_invites(responses)
      allow(Faraday).to receive(:post) do |url, &block|
        req = Struct.new(:headers, :body).new({}, nil)
        block&.call(req)
        channel = req.body[/name="channel"\r\n\r\n(\w+)/, 1]
        invited << [url, channel]
        response = responses.fetch(channel)
        raise response if response.is_a?(Exception)

        instance_double(Faraday::Response, body: response.is_a?(String) ? response : response.to_json)
      end
    end

    it "invites the user to every member channel" do
      stub_invites("C1" => { ok: true }, "C2" => { ok: true }, "C3" => { ok: true })

      expect(service.add_to_channels("U1")).to eq({})
      expect(invited).to eq(%w[C1 C2 C3].map { |c| ["https://patchworklabs.slack.com/api/conversations.invite", c] })
    end

    it "treats a channel the user is already in as done, and keeps going after a failure" do
      stub_invites("C1" => { ok: false, error: "already_in_channel" }, "C2" => Faraday::ConnectionFailed.new("down"),
                   "C3" => { ok: false, error: "not_in_channel" })

      expect(service.add_to_channels("U1")).to eq("C2" => "request_failed", "C3" => "not_in_channel")
    end

    it "counts an answer that is not JSON as a failure" do
      stub_invites("C1" => "<html>rate limited</html>")

      expect(service.add_to_channels("U1", %w[C1])).to eq("C1" => "request_failed")
    end
  end

  describe "#member_channels" do
    it "is the production list in production" do
      allow(Rails.env).to receive(:production?).and_return(true)

      expect(service.send(:member_channels)).to eq(SlackService::DEFAULT_CHANNELS.values)
    end

    it "reads the staging credentials on staging" do
      allow(Weave).to receive(:staging?).and_return(true)
      allow(service).to receive(:default_channels).and_return(%w[CS1 CS2])

      expect(service.send(:member_channels)).to eq(%w[CS1 CS2])
    end

    it "is empty in development and test" do
      expect(service.send(:member_channels)).to eq([])
    end
  end
end
