# frozen_string_literal: true

require "rails_helper"

RSpec.describe KnotSettings do
  def values_for(environment)
    Rails.application.config_for(described_class::PATH, env: environment)
  end

  it "keeps a Knot for ever: no expiry in any environment" do
    expect(described_class.keep_years).to be_nil
    expect(described_class).to be_kept_forever
    %w[development test production].each { |environment| expect(values_for(environment)[:keep_years]).to be_nil }
  end

  it "keeps the locked Ganymede cap, and no patch lead list: a patch lead is a role" do
    %w[development test production].each do |environment|
      expect(values_for(environment).dig(:programs, :ganymede, :grant_cap)).to eq(1)
      expect(values_for(environment).dig(:programs, :ganymede)).not_to have_key(:patch_lead_p_ids)
    end
  end

  it "refuses the old patch_lead_p_ids key with a clear error" do
    allow(described_class).to receive(:config)
      .and_return({ programs: { ganymede: { name: "Project Ganymede", grant_cap: 1, patch_lead_p_ids: ["PWL1"] } } })

    expect { described_class.programs }.to raise_error(ArgumentError, /patch_lead_p_ids is gone/)
  end
end
