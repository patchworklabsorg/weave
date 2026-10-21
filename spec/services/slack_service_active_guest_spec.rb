# frozen_string_literal: true

require "rails_helper"

RSpec.describe SlackService do
  let(:client) { instance_double(Slack::Web::Client) }

  def service_with(client)
    described_class.allocate.tap { |service| service.instance_variable_set(:@client, client) }
  end

  def slack_user(**fields)
    allow(client).to receive(:users_info).with(user: "U1").and_return("ok" => true, "user" => { "id" => "U1", **fields.transform_keys(&:to_s) })
  end

  describe "#active_guest?" do
    it "is true for a single-channel guest" do
      slack_user(is_ultra_restricted: true)

      expect(service_with(client).active_guest?("U1")).to be(true)
    end

    it "is false for a full member" do
      slack_user

      expect(service_with(client).active_guest?("U1")).to be(false)
    end

    it "is false for a deleted guest" do
      slack_user(is_ultra_restricted: true, deleted: true)

      expect(service_with(client).active_guest?("U1")).to be(false)
    end

    it "is false for an unknown user" do
      allow(client).to receive(:users_info).and_raise(Slack::Web::Api::Errors::UserNotFound, "user_not_found")

      expect(service_with(client).active_guest?("U1")).to be(false)
    end
  end
end
