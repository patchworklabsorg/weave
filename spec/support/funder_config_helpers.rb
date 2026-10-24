# frozen_string_literal: true

# Runs a block (and the rest of the example) with other funder profiles or program funders than
# config/kyc/data_retention.yml has for test (see FunderProfiles).
module FunderConfigHelpers
  def with_funder_config(funders: nil, program_funders: nil)
    config = DataRetention.config.deep_dup
    config[:funders] = funders.deep_symbolize_keys unless funders.nil?
    config[:program_funders] = program_funders.deep_symbolize_keys unless program_funders.nil?
    allow(DataRetention).to receive(:config).and_return(config)
    yield config
  end
end

RSpec.configure { |config| config.include FunderConfigHelpers }
