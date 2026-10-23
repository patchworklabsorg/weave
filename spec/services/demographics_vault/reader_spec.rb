# frozen_string_literal: true

require "rails_helper"

RSpec.describe DemographicsVault::Reader do
  let(:pem) { DemographicsKeys::PRIVATE_KEY.private_to_pem }

  it "reads the private key from the environment of the reporting run" do
    expect(described_class.from_env(described_class::ENV_PEM => pem).key_id).to eq(demographics_reader.key_id)
  end

  it "reads the private key from a file" do
    Tempfile.create("key") do |file|
      file.write(pem)
      file.flush

      expect(described_class.from_env(described_class::ENV_FILE => file.path).key_id).to eq(demographics_reader.key_id)
    end
  end

  it "refuses to start without a key" do
    expect { described_class.from_env({}) }.to raise_error(described_class::KeyUnavailable)
  end

  it "refuses a public key" do
    expect { described_class.new(DemographicsKeys::PRIVATE_KEY.public_to_pem) }.to raise_error(described_class::KeyUnavailable)
  end

  it "never prints the key" do
    expect(demographics_reader.inspect).not_to include("PRIVATE")
  end
end
