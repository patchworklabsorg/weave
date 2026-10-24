# frozen_string_literal: true

# A key pair for the demographics vault in specs (see DemographicsVault). The
# app side gets only the public key, as in production. Specs that act as the
# reporting run use demographics_reader.
module DemographicsKeys
  PRIVATE_KEY = OpenSSL::PKey::RSA.generate(2048)

  def demographics_reader = DemographicsVault::Reader.new(PRIVATE_KEY.private_to_pem)
end

RSpec.configure do |config|
  config.include DemographicsKeys

  config.before do
    DemographicsVault.reset!
    DemographicsVault.public_key = OpenSSL::PKey.read(DemographicsKeys::PRIVATE_KEY.public_to_pem)
  end
end
