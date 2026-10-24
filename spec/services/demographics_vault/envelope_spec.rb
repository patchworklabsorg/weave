# frozen_string_literal: true

require "rails_helper"

RSpec.describe DemographicsVault::Envelope do
  let(:public_key) { DemographicsVault.public_key }
  let(:payload) { { "answers" => { "gender_identity" => "woman" } } }

  it "opens with the private key and gives back the payload" do
    envelope = described_class.seal(payload, public_key)

    expect(demographics_reader.open(envelope)).to eq(payload)
  end

  it "uses a new data key each time, so equal answers give different envelopes" do
    expect(described_class.seal(payload, public_key)).not_to eq(described_class.seal(payload, public_key))
  end

  it "does not open with another key" do
    envelope = described_class.seal(payload, public_key)
    other = DemographicsVault::Reader.new(OpenSSL::PKey::RSA.generate(2048).private_to_pem)

    expect { other.open(envelope) }.to raise_error(described_class::Unreadable)
  end

  it "does not open when the ciphertext was changed" do
    parts = JSON.parse(described_class.seal(payload, public_key))
    bytes = Base64.strict_decode64(parts["ct"])
    bytes.setbyte(0, bytes.getbyte(0) ^ 1)
    parts["ct"] = Base64.strict_encode64(bytes)

    expect { demographics_reader.open(parts.to_json) }.to raise_error(described_class::Unreadable)
  end

  it "refuses a payload that does not fit the padding" do
    expect { described_class.seal({ "x" => "y" * 3000 }, public_key) }.to raise_error(described_class::TooLarge)
  end

  it "names the key pair with the same id from either half" do
    expect(described_class.key_id(public_key)).to eq(demographics_reader.key_id)
  end
end
