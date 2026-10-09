# frozen_string_literal: true

require "rails_helper"

RSpec.describe SlackService do
  let(:client) { instance_double(Slack::Web::Client) }

  def service_with(client)
    described_class.allocate.tap { |service| service.instance_variable_set(:@client, client) }
  end

  describe "#find_email" do
    it "returns the email from users.info" do
      allow(client).to receive(:users_info).with(user: "U123")
                                           .and_return("ok" => true, "user" => { "id" => "U123", "profile" => { "email" => "a@example.com" } })

      expect(service_with(client).find_email("U123")).to eq("a@example.com")
    end

    it "returns nil when the profile has no email" do
      allow(client).to receive(:users_info).with(user: "U123")
                                           .and_return("ok" => true, "user" => { "id" => "U123", "profile" => {} })

      expect(service_with(client).find_email("U123")).to be_nil
    end

    it "returns nil for an unknown user" do
      allow(client).to receive(:users_info).and_raise(Slack::Web::Api::Errors::UserNotFound, "user_not_found")

      expect(service_with(client).find_email("U404")).to be_nil
    end

    it "raises other Slack errors so the webhook job can retry" do
      allow(client).to receive(:users_info).and_raise(Slack::Web::Api::Errors::SlackError, "fatal_error")

      expect { service_with(client).find_email("U123") }.to raise_error(SlackService::ApiError)
    end

    it "raises without a bot client" do
      expect { service_with(nil).find_email("U123") }.to raise_error(SlackService::ConfigurationError)
    end
  end
end
