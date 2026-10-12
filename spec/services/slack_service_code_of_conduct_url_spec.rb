# frozen_string_literal: true

require "rails_helper"

RSpec.describe SlackService, ".code_of_conduct_url" do
  around do |example|
    original = ENV.fetch("SLACK_COC_URL", nil)
    example.run
  ensure
    ENV["SLACK_COC_URL"] = original
  end

  it "links to the Code of Conduct on the website when nothing is configured" do
    ENV["SLACK_COC_URL"] = ""
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:slack, :coc_url).and_return(nil)

    expect(described_class.code_of_conduct_url).to eq("https://patchworklabs.org/conduct")
  end

  it "uses SLACK_COC_URL when it is set" do
    ENV["SLACK_COC_URL"] = "https://example.org/coc"

    expect(described_class.code_of_conduct_url).to eq("https://example.org/coc")
  end
end
