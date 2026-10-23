# frozen_string_literal: true

require "rails_helper"

RSpec.describe DemographicsHelper, type: :helper do
  it "labels each locked age band" do
    labels = %w[0-12 13-15 16-17 18-24 25-34 35+].map { |band| helper.demographic_option_label("age_band", band) }

    expect(labels).to eq(["Under 13", "13 to 15", "16 to 17", "18 to 24", "25 to 34", "35 and older"])
    expect(helper.demographic_option_label("age_band", "unknown")).to eq("Unknown")
  end
end
