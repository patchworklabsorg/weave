# frozen_string_literal: true

require "rails_helper"

# The value Jasper locked on 2026-10-12. Tests use a smaller threshold, so
# this spec reads the production config. Counsel can still change the value in
# config/demographics.yml. Then change this spec too.
RSpec.describe DemographicsVault do
  it "hides groups under 10 in production (config/demographics.yml)" do
    production = Rails.application.config_for(:demographics, env: "production")

    expect(production[:small_count_threshold]).to eq(10)
  end
end
