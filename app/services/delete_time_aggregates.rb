# frozen_string_literal: true

# The delete-time aggregates (proposal section 06, "Participation data and
# grant reporting"). Before the deletion pipeline severs an identity, it adds
# the member's generalized bands to these running totals:
#
#   program, year, outcome, age band (not the birth date), region (country,
#   not the address), amount band (not the exact figure)
#
# The table holds counts only: no row per person and no identifier, so
# nothing joins back to a person. The demographic bands do not come here:
# the app can't open the vault, so DemographicsVault.fold! parks the sealed
# envelope for the next reporting run (see docs/KYC.md).
#
# Reports read the totals through the same small-count suppression as the
# vault (DemographicsReport.suppress with the vault's threshold).
module DeleteTimeAggregates
  DIMENSIONS = %i[program year outcome age_band region amount_band].freeze
  REPORT_FIELDS = %w[outcome age_band region amount_band].freeze
  UNKNOWN = "unknown"

  Bands = Data.define(*DIMENSIONS)

  class << self
    # The bands of one participation. A retained record (account gone)
    # carries its own bands.
    def bands_for(participation, user: participation.user)
      if user.nil?
        return Bands.new(program: participation.program, year: participation.year, outcome: participation.outcome,
                         age_band: participation.age_band.presence || UNKNOWN,
                         region: participation.region.presence || UNKNOWN,
                         amount_band: participation.amount_band.presence || "none")
      end

      Bands.new(program: participation.program, year: participation.year, outcome: participation.outcome,
                age_band: DemographicsVault.age_band(user.birthday, on: Date.new(participation.year, 12, 31)),
                region: region(user), amount_band: amount_band(user, participation))
    end

    # Adds one to the cell of these bands.
    def add!(bands)
      DeleteTimeAggregate.upsert( # rubocop:disable Rails/SkipsModelValidations
        bands.to_h.merge(count: 1),
        unique_by: :index_delete_time_aggregates_on_bands,
        on_duplicate: Arel.sql("count = delete_time_aggregates.count + 1")
      )
    end

    # The member's region, generalized to the country of their address.
    def region(user)
      # Address#country is an ISO3166::Country, so read the stored code.
      code = [user.shipping_address, user.billing_address].compact.map { |address| address[:country].to_s.strip }.find(&:present?)
      code ? code.upcase : UNKNOWN
    end

    def amount_band(user, participation)
      cents = GrantDisbursement.where(user:, program: participation.program)
                               .where(disbursed_on: Date.new(participation.year, 1, 1)..Date.new(participation.year, 12, 31))
                               .sum(:amount_cents)
      DataRetention.amount_band(cents)
    end

    # Suppressed totals per cohort ("ganymede-2026") and for all departed
    # members. Each cohort is a tally in the shape DemographicsReport.suppress
    # takes: respondents and counts per field.
    def report(threshold: DemographicsVault.small_count_threshold)
      cells = DeleteTimeAggregate.all.to_a
      cohorts = cells.group_by { |cell| "#{cell.program}-#{cell.year}" }.sort.to_h
      {
        "threshold" => threshold,
        "all"       => DemographicsReport.suppress(tally(cells), threshold),
        "cohorts"   => cohorts.transform_values { |group| DemographicsReport.suppress(tally(group), threshold) }
      }
    end

    private

    def tally(cells)
      fields = REPORT_FIELDS.index_with { {} }
      cells.each do |cell|
        REPORT_FIELDS.each do |field|
          value = cell.public_send(field)
          fields[field][value] = fields[field].fetch(value, 0) + cell.count
        end
      end
      { "respondents" => cells.sum(&:count), "fields" => fields }
    end

  end
end
