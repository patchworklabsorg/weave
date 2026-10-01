# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActiveSupport::ParameterFilter do # rubocop:disable RSpec/SpecFilePathFormat
  let(:filter) { described_class.new(Rails.application.config.filter_parameters) }

  it "filters the legal name from logs" do
    params = { user: { first_name: "John", legal_first_name: "Jonathan", legal_last_name: "Dorian" } }

    expect(filter.filter(params)).to eq(
      user: { first_name: "John", legal_first_name: "[FILTERED]", legal_last_name: "[FILTERED]" }
    )
  end
end
