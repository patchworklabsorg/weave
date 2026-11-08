# frozen_string_literal: true

require "rails_helper"

RSpec.describe VerificationIdentifiers do
  let(:params) do
    {
      document_type: "passport", issuing_country: "de", document_number: " C01X00T47 ", national_id: "",
      legal_name: "Erika Mustermann", date_of_birth: "1990-08-12", country_of_birth: "de"
    }
  end

  it "reads the decision form" do
    identifiers = described_class.from_params(params)

    expect(identifiers).to have_attributes(issuing_country: "DE", document_number: "C01X00T47", national_id: nil,
                                           date_of_birth: Date.new(1990, 8, 12), country_of_birth: "DE")
    expect(identifiers).to be_valid
  end

  it "reports missing and bad values" do
    identifiers = described_class.from_params(params.merge(document_number: "", issuing_country: "Germany", date_of_birth: "12/08/1990"))

    expect(identifiers.errors.keys).to contain_exactly(:document_number, :issuing_country, :date_of_birth)
  end

  describe "a country with a lifetime national identity number" do
    let(:polish) { params.merge(issuing_country: "pl") }

    it "needs the national identity number" do
      identifiers = described_class.from_params(polish)

      expect(identifiers).not_to be_valid
      expect(identifiers.errors.keys).to eq([:national_id])
    end

    it "accepts the number" do
      expect(described_class.from_params(polish.merge(national_id: "90081212345"))).to be_valid
    end

    it "accepts the verifier's confirmation that the document does not show one" do
      expect(described_class.from_params(polish.merge(national_id_absent: "1"))).to be_valid
    end

    it "does not need the number for other countries" do
      expect(described_class.from_params(params.merge(issuing_country: "us"))).to be_valid
    end

    it "defaults the confirmation to no when it is not given" do
      identifiers = described_class.new(document_type: "passport", issuing_country: "PL", document_number: "EA1234567",
                                        national_id: nil, legal_name: "Adam Sidwa", date_of_birth: Date.new(1990, 8, 12),
                                        country_of_birth: "PL")

      expect(identifiers.national_id_absent).to be(false)
      expect(identifiers).not_to be_valid
    end
  end

  describe "country of birth" do
    it "is required" do
      expect(described_class.from_params(params.merge(country_of_birth: "")).errors.keys).to eq([:country_of_birth])
    end

    it "accepts the verifier's confirmation that the document does not show a place of birth" do
      expect(described_class.from_params(params.merge(country_of_birth: "", country_of_birth_absent: "1"))).to be_valid
    end

    it "needs two letters" do
      expect(described_class.from_params(params.merge(country_of_birth: "Poland")).errors.keys).to eq([:country_of_birth])
    end
  end

  describe "a US driving licence" do
    let(:licence) { params.merge(document_type: "driving_licence", issuing_country: "us") }

    it "needs the state" do
      expect(described_class.from_params(licence).errors.keys).to eq([:issuing_region])
    end

    it "accepts a two-letter state" do
      expect(described_class.from_params(licence.merge(issuing_region: "ca"))).to have_attributes(issuing_region: "CA", valid?: true)
    end

    it "does not need a state for a passport" do
      expect(described_class.from_params(params.merge(issuing_country: "us"))).to be_valid
    end
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
