# frozen_string_literal: true

# The open values of the Knot and its program grants, from
# config/kyc/knot.yml (see docs/KYC.md).
module KnotSettings
  PATH = Rails.root.join("config/kyc/knot.yml")

  # grant_cap nil means no cap.
  Program = Data.define(:key, :name, :grant_cap, :patch_lead_p_ids)

  class << self
    def config = @config ||= Rails.application.config_for(PATH)

    def programs
      config.fetch(:programs).to_h.map do |key, values|
        Program.new(key: key.to_s, name: values.fetch(:name), grant_cap: values[:grant_cap],
                    patch_lead_p_ids: Array(values[:patch_lead_p_ids]).map(&:to_s))
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
