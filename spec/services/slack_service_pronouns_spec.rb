# frozen_string_literal: true

require "rails_helper"

RSpec.describe SlackService do
  let(:user_client) { instance_double(Slack::Web::Client) }

  def service_with(user_client)
    described_class.allocate.tap { |service| service.instance_variable_set(:@user_client, user_client) }
  end

  describe "#update_slack_pronouns" do
    it "sets the standard Slack pronouns field" do
      expect(user_client).to receive(:users_profile_set)
        .with(user: "U123", profile: { pronouns: "they/them" }.to_json)

      expect(service_with(user_client).update_slack_pronouns("U123", "they/them")).to be true
    end

    it "sends an empty value to clear the field" do
      expect(user_client).to receive(:users_profile_set).with(user: "U123", profile: { pronouns: "" }.to_json)

      service_with(user_client).update_slack_pronouns("U123", nil)
    end

    it "does nothing without a user token" do
      expect(service_with(nil).update_slack_pronouns("U123", "they/them")).to be false
    end

    it "raises Slack errors so the job can retry" do
      allow(user_client).to receive(:users_profile_set).and_raise(Slack::Web::Api::Errors::SlackError, "fatal_error")

      expect { service_with(user_client).update_slack_pronouns("U123", "they/them") }
        .to raise_error(Slack::Web::Api::Errors::SlackError)
    end

    it "raises rate limit errors so the job can retry" do
      response = instance_double(Faraday::Response, headers: { "retry-after" => "30" })
      allow(user_client).to receive(:users_profile_set)
        .and_raise(Slack::Web::Api::Errors::TooManyRequestsError.new(response))

      expect { service_with(user_client).update_slack_pronouns("U123", "they/them") }
        .to raise_error(Slack::Web::Api::Errors::TooManyRequestsError)
    end
  end

  describe "#sync_slack_users_to_idp pronouns" do
    def sync(member)
      service = service_with(nil)
      allow(service).to receive_messages(configured?: true, list_members: [
                                           { "updated" => 1.year.ago.to_i }.merge(member)
                                         ])
      service.sync_slack_users_to_idp
    end

    it "keeps Weave's pronouns and pushes them when the sync first links the account" do
      user = create(:user, :verified, email: "link@example.com", pronouns: "they/them")

      expect do
        sync("id" => "U700", "profile" => { "email" => "link@example.com", "pronouns" => "he/him" })
      end.to have_enqueued_job(PushPronounsToSlackJob).with(user.id)

      expect(user.reload.pronouns).to eq("they/them")
    end

    it "takes Slack's pronouns when the sync first links an account without any" do
      user = create(:user, :verified, email: "fill@example.com")

      sync("id" => "U701", "profile" => { "email" => "fill@example.com", "pronouns" => "he/him" })

      expect(user.reload.pronouns).to eq("he/him")
    end

    it "does not revert a Weave edit whose push failed" do
      user = create(:user, :verified, email: "edit@example.com", slack_id: "U702")
      user.apply_slack_pronouns!("he/him")
      user.update!(pronouns: "they/them")

      sync("id" => "U702", "profile" => { "email" => "edit@example.com", "pronouns" => "he/him" })

      expect(user.reload.pronouns).to eq("they/them")
    end
  end
end
