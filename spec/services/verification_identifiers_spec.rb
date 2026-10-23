# frozen_string_literal: true

require "rails_helper"

RSpec.describe VerificationIdentifiers do
  let(:params) do
    {
      document_type: "passport", issuing_country: "de", document_number: " C01X00T47 ", national_id: "",
      legal_name: "Erika Mustermann", date_of_birth: "1990-08-12"
    }
  end

  it "reads the decision form" do
    identifiers = described_class.from_params(params)

    expect(identifiers).to have_attributes(issuing_country: "DE", document_number: "C01X00T47", national_id: nil,
                                           date_of_birth: Date.new(1990, 8, 12))
    expect(identifiers).to be_valid
  end

  it "reports missing and bad values" do
    identifiers = described_class.from_params(params.merge(document_number: "", issuing_country: "Germany", date_of_birth: "12/08/1990"))

    expect(identifiers.errors.keys).to contain_exactly(:document_number, :issuing_country, :date_of_birth)
  end

  it "hides the values when inspected or logged" do
    identifiers = described_class.from_params(params)

    expect(identifiers.inspect).not_to include("C01X00T47")
    expect(identifiers.to_s).not_to include("Mustermann")
  end

  it "is filtered from request logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    filtered = filter.filter(identifiers: params)[:identifiers]

    expect(filtered.values_at(:document_number, :national_id, :legal_name, :date_of_birth, :issuing_country)).to all(eq("[FILTERED]"))
  end

  it "filters the uploaded ID image, whose file name can hold the member's name" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)

    expect(filter.filter(id_document: "jane_doe_passport.png")[:id_document]).to eq("[FILTERED]")
  end
end
