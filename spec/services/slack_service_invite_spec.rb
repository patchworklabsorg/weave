# frozen_string_literal: true

require "rails_helper"

RSpec.describe SlackService do
  subject(:service) { described_class.new }

  before do
    allow(service).to receive_messages(
      browser_token: "xoxc-test",
      slack_cookie: "xoxd-test",
      team_id: "T123",
      workspace_subdomain: "patchworklabs",
      coc_channel: "C_COC",
      default_channels: ["C_DEFAULT"]
    )
  end

  # Capture the request Faraday builds and return a canned response body.
  def stub_faraday(response_body)
    allow(Faraday).to receive(:post) do |url, &block|
      req = Struct.new(:headers, :body).new({}, nil)
      block&.call(req)
      @url = url
      @body = req.body
      instance_double(Faraday::Response, body: response_body.to_json)
    end
  end

  describe "#invite_to_workspace" do
    it "posts single-channel guests to the inviteBulk endpoint as ultra_restricted in the CoC channel" do
      stub_faraday("ok" => true, "invites" => [{ "email" => "a@b.co", "ok" => true }])

      result = service.invite_to_workspace(email: "a@b.co", guest: :single_channel)

      expect(@url).to eq("https://patchworklabs.slack.com/api/users.admin.inviteBulk")
      expect(@body).to include('name="ultra_restricted"')
      expect(@body).to include('"type":"ultra_restricted"')
      expect(@body).to include("C_COC")
      expect(result[:ok]).to be true
      expect(result[:already_member]).to be false
    end

    it "treats already_in_team as a successful no-op" do
      stub_faraday("ok" => true, "invites" => [{ "ok" => false, "error" => "already_in_team" }])

      result = service.invite_to_workspace(email: "a@b.co")

      expect(result[:ok]).to be true
      expect(result[:already_member]).to be true
    end

    it "surfaces a hard failure" do
      stub_faraday("ok" => true, "invites" => [{ "ok" => false, "error" => "invalid_auth" }])

      result = service.invite_to_workspace(email: "a@b.co")

      expect(result[:ok]).to be false
      expect(result[:error]).to eq("invalid_auth")
    end

    it "raises ConfigurationError when browser credentials are missing" do
      allow(service).to receive(:browser_token).and_return(nil)
      expect { service.invite_to_workspace(email: "a@b.co") }.to raise_error(SlackService::ConfigurationError)
    end
  end

  describe "#promote_to_member" do
    it "calls setRegular and reports success" do
      stub_faraday("ok" => true)
      result = service.promote_to_member("U123")
      expect(@url).to eq("https://patchworklabs.slack.com/api/users.admin.setRegular")
      expect(@body).to include("U123")
      expect(result[:ok]).to be true
    end

    it "reports failure with the Slack error" do
      stub_faraday("ok" => false, "error" => "user_not_found")
      expect(service.promote_to_member("U123")).to include(ok: false, error: "user_not_found")
    end
  end
end
