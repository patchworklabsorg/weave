# frozen_string_literal: true

# Labels for the demographics questions and report (see DemographicsVault).
module DemographicsHelper
  def demographic_field_label(key)
    t("demographics.fields.#{key}.label", default: key.to_s.humanize)
  end

  def demographic_option_label(key, value)
    return demographic_age_band_label(value) if key.to_s == "age_band"

    t("demographics.fields.#{key}.options.#{value}",
      default: [:"demographics.options.#{value}", value.to_s.humanize])
  end

  # "0-12" reads "Under 13", "13-15" reads "13 to 15", "35+" reads "35 and
  # older" (see DemographicsVault.age_band).
  def demographic_age_band_label(value)
    case value.to_s
    when /\A0-(\d+)\z/ then t("demographics.age_bands.under", age: Regexp.last_match(1).to_i + 1)
    when /\A(\d+)-(\d+)\z/ then t("demographics.age_bands.range", from: Regexp.last_match(1), to: Regexp.last_match(2))
    when /\A(\d+)\+\z/ then t("demographics.age_bands.open", from: Regexp.last_match(1))
    else t("demographics.options.#{value}", default: value.to_s.humanize)
    end
  end

  # A count from a report: nil means it was hidden by small-count suppression.
  def demographic_count(count, threshold)
    count.nil? ? "hidden (fewer than #{threshold}, or hidden to protect one)" : number_with_delimiter(count)
  end
end
