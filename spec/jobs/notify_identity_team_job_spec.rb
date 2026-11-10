# frozen_string_literal: true

require "rails_helper"

RSpec.describe NotifyIdentityTeamJob do
  let(:service) { instance_double(SlackService, configured?: true, identity_channel: "CIDENTITY") }
  let(:member) { create(:user, :verified, first_name: "Ada") }
  let(:verifier) { create(:user, :identity_team, first_name: "Robin", last_name: "Okafor") }
  let(:verification) { create(:verification, user: member) }

  before { allow(SlackService).to receive(:new).and_return(service) }

  describe "the member's thread" do
    it "starts the thread with the first notice, under the member's Weave ID, with no member name" do
      expect(service).to receive(:post_to_identity_channel) do |text, **options|
        expect(options).to be_empty
        expect(text).to include("Weave ID #{member.p_id}", "waits for pre-review", "#{Weave.url}/identity/verifications/",
                                verification.public_id)
        expect(text).not_to include("Ada", member.email)
        "1700000000.000100"
      end

      described_class.perform_now("verification_submitted", verification)

      expect(IdentitySlackThread.find_by(user: member, channel: "CIDENTITY").ts).to eq("1700000000.000100")
    end

    it "posts the next notices as replies in the thread, and names the team member" do
      IdentitySlackThread.create!(user: member, channel: "CIDENTITY", ts: "1700000000.000100")
      expect(service).to receive(:post_to_identity_channel)
        .with(a_string_including("Robin Okafor took", verification.public_id), thread_ts: "1700000000.000100", broadcast: false)

      described_class.perform_now("pre_review_started", verification, actor: verifier)
    end

    it "also sends new work to the channel, so a new attempt in an old thread is seen" do
      IdentitySlackThread.create!(user: member, channel: "CIDENTITY", ts: "1700000000.000100")
      expect(service).to receive(:post_to_identity_channel).with(anything, thread_ts: "1700000000.000100", broadcast: true)

      described_class.perform_now("verification_submitted", verification)
    end

    it "shows the call time in each reader's time zone" do
      IdentitySlackThread.create!(user: member, channel: "CIDENTITY", ts: "1")
      at = Time.utc(2026, 11, 12, 15, 30)
      expect(service).to receive(:post_to_identity_channel)
        .with(a_string_including("<!date^#{at.to_i}^", "|2026-11-12 15:30 UTC>"), thread_ts: "1", broadcast: false)

      described_class.perform_now("call_scheduled", verification, actor: verifier, at:)
    end

    it "starts a new thread in a new channel" do
      IdentitySlackThread.create!(user: member, channel: "COLD", ts: "1")
      allow(service).to receive(:post_to_identity_channel) { |text| text.include?("Weave ID") ? "2" : raise("not a new thread") }

      described_class.perform_now("verification_submitted", verification)

      expect(IdentitySlackThread.find_by(user: member, channel: "CIDENTITY").ts).to eq("2")
    end

    it "starts a new thread when the parent message is gone" do
      thread = IdentitySlackThread.create!(user: member, channel: "CIDENTITY", ts: "1")
      allow(service).to receive(:post_to_identity_channel) do |text, thread_ts: nil, **|
        raise Slack::Web::Api::Errors::SlackError, "thread_not_found" if thread_ts == "1"

        text.include?("Weave ID") ? "2" : raise("not a new thread")
      end

      described_class.perform_now("escalated", verification)

      expect(thread.reload.ts).to eq("2")
    end

    it "posts to the channel, with no thread, for an attempt whose account was deleted" do
      verification.update!(user: nil)
      expect(service).to receive(:post_to_identity_channel).with(a_string_including(verification.public_id))

      described_class.perform_now("escalated", verification)
    end

    it "keeps no thread when the first post fails, so the next notice starts it" do
      allow(service).to receive(:post_to_identity_channel).and_raise(Slack::Web::Api::Errors::SlackError.new("not_in_channel"))

      described_class.perform_now("verification_submitted", verification)

      expect(IdentitySlackThread.find_by(user: member)&.ts).to be_nil
    end
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

  it "renders the text of every kind with the values its callers pass" do
    values = { link: "x", actor: "y", at: "z", outcome: "verified", resolution: "retry allowed" }
    described_class::KINDS.each do |kind|
      expect { I18n.t("verification.slack.team.#{kind}", raise: true, **values) }.not_to raise_error, kind
    end
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
    error = Slack::Web::Api::Errors::TooManyRequestsError.new(Struct.new(:headers).new({ "retry-after" => "1" }))
    allow(service).to receive(:post_to_identity_channel).and_raise(error)

    expect { described_class.perform_now("escalated", verification) }.to have_enqueued_job(described_class)
  end
end
