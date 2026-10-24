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

  it "names Adam as the Ganymede patch lead in production only" do
    expect(values_for("production").dig(:programs, :ganymede, :patch_lead_p_ids)).to eq(["PWL8724F96B89"])
    expect(values_for("production").dig(:programs, :ganymede, :grant_cap)).to eq(1)
    expect(values_for("test").dig(:programs, :ganymede, :patch_lead_p_ids)).to eq([])
  end
end
