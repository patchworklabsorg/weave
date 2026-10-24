# frozen_string_literal: true

# The open values of the Knot and its program grants, from
# config/kyc/knot.yml (see docs/KYC.md).
module KnotSettings
  PATH = Rails.root.join("config/kyc/knot.yml")

  # grant_cap nil means no cap. The patch lead of a program is a role (see
  # KnotGrants.patch_lead?), not a value here.
  Program = Data.define(:key, :name, :grant_cap)

  class << self
    def config = @config ||= Rails.application.config_for(PATH)

    def programs
      config.fetch(:programs).to_h.map do |key, values|
        if values.key?(:patch_lead_p_ids)
          raise ArgumentError, "#{PATH}: programs.#{key}.patch_lead_p_ids is gone. A patch lead is a patch_lead role scoped to the program (see config/roles.yml)."
        end

        Program.new(key: key.to_s, name: values.fetch(:name), grant_cap: values[:grant_cap])
      end
    end

    def program(key) = programs.find { |program| program.key == key.to_s }

    def program_keys = programs.map(&:key)

    # Years Weave keeps a Knot, or nil for ever (the locked value). Nothing
    # deletes a Knot: the grant cap and the blacklist flag depend on it.
    def keep_years = config[:keep_years]

    def kept_forever? = keep_years.nil?

    # For specs that change a value.
    def reset! = @config = nil

  end
end
