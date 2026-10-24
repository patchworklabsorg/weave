# frozen_string_literal: true

require "rails_helper"

# Jasper locked most values in config/thread_count.yml on 2026-10-12. Their
# signs and order are part of the design (proposal v0.8, section 05). Counsel
# can still change a value in the config. Then change this spec too.
RSpec.describe ThreadCount::Config do
  let(:config) { described_class.current }

  it "uses the locked values" do
    expect(config.member_vouch_threshold).to eq(75)
    expect((ThreadCount::Entry::KINDS - ["project_blacklisted"]).map { |kind| config.half_life_days(kind) }).to all(eq(1095))
    expect(config.half_life_days("project_blacklisted")).to be_nil
    expect(config.no_decay_kinds).to eq(["project_blacklisted"])
    expect(%w[project_approved project_exceptional project_denied project_blacklisted].map { |kind| config.weight(kind) })
      .to eq([10, 20, -5, -40])
    expect(config.levels("moderation_case").map { |level| config.weight("moderation_case", level) })
      .to all(be_between(-40, -10))
  end

  it "reads config/thread_count.yml" do
    expect(config.member_vouch_threshold).to be > 0
    expect(config.half_life_days("staff_vouch")).to be > 0
  end

  it "adds score for vouches, approvals and external signals" do
    expect(config.weight("board_vouch")).to be > 0
    expect(config.weight("member_vouch")).to be > 0
    expect(config.weight("project_approved")).to be > 0
    expect(config.weight("project_exceptional")).to be > 0
    config.levels("external_signal").each { |level| expect(config.weight("external_signal", level)).to be >= 0 }
  end

  it "removes score for denials, blacklists and moderation cases" do
    expect(config.weight("project_denied")).to be < 0
    expect(config.weight("project_blacklisted")).to be < config.weight("project_denied")
    config.levels("moderation_case").each { |level| expect(config.weight("moderation_case", level)).to be <= 0 }
  end

  it "gives a reversal no weight" do
    expect(config.weight("reversal")).to eq(0)
  end

  it "raises for a kind or level it does not know" do
    expect { config.weight("staff_vouch", "intern") }.to raise_error(described_class::UnknownWeight)
    expect { config.weight("bribe") }.to raise_error(described_class::UnknownWeight)
  end

  it "lets a kind never fade through the no-decay list" do
    described_class.with(no_decay_kinds: %w[project_denied]) do
      expect(described_class.current.half_life_days("project_denied")).to be_nil
      expect(described_class.current.half_life_days("project_blacklisted")).to eq(1095)
    end
  end

  it "lets a kind never fade" do
    described_class.with(half_life_days_by_kind: { project_blacklisted: nil }) do
      expect(described_class.current.half_life_days("project_blacklisted")).to be_nil
    end
  end

  it "lets no service send project events until one is named, outside the test environment" do
    values = YAML.safe_load_file(Rails.root.join("config/thread_count.yml"), aliases: true)

    expect(values.dig("shared", "project_event_services")).to eq([])
  end
end
