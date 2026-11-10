# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotifyIdentityTeamJob do
  let(:service) { instance_double(SlackService, configured?: true, identity_channel: "CIDENTITY") }
  let(:member) { create(:user, :verified, first_name: "Ada") }
  let(:verification) { create(:verification, user: member) }

  before { allow(SlackService).to receive(:new).and_return(service) }

  it "posts a link to the verification page, with no member name" do
    expect(service).to receive(:post_to_identity_channel) do |text|
      expect(text).to include("waits for pre-review", "#{Weave.url}/identity/verifications/", verification.public_id)
      expect(text).not_to include("Ada", member.email)
    end

    described_class.perform_now("verification_submitted", verification)
  end

  it "links a residency check to its own page" do
    active_key_set_without_holders # ID checks open only after the key ceremony.
    create(:verification, :verified, user: member)
    upload = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/id_document.png"), "image/png")
    result = ResidencyFlow.submit_document(member, document: upload, evidence_type: "school_enrollment")
    expect(result).to be_success, result.errors.inspect
    check = result.verification
    expect(service).to receive(:post_to_identity_channel).with(a_string_including("/identity/residency_checks/", check.public_id))

    described_class.perform_now("residency_submitted", check)
  end

  it "does nothing when no identity channel is set" do
    allow(service).to receive(:identity_channel).and_return(nil)
    expect(service).not_to receive(:post_to_identity_channel)

    described_class.perform_now("verification_submitted", verification)
  end

  it "logs a setup problem at error level, so a missing scope or channel is not lost" do
    allow(service).to receive(:post_to_identity_channel).and_raise(Slack::Web::Api::Errors::SlackError.new("not_in_channel"))
    expect(Rails.logger).to receive(:error).with(/not_in_channel/)

    described_class.perform_now("escalated", verification)
  end

  it "retries a Slack rate limit, and does not swallow it" do
    allow(service).to receive(:post_to_identity_channel).and_raise(Slack::Web::Api::Errors::TooManyRequestsError.new(Struct.new(:headers).new({ "retry-after" => "1" })))

    expect { described_class.perform_now("escalated", verification) }.to have_enqueued_job(described_class)
  end

  it "logs and stops when Slack refuses the post" do
    allow(service).to receive(:post_to_identity_channel).and_raise(Slack::Web::Api::Errors::SlackError.new("not_in_channel"))

    expect { described_class.perform_now("escalated", verification) }.not_to raise_error
  end
end
