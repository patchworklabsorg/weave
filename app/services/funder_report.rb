# frozen_string_literal: true

# The aggregate report for one funder (see FunderProfiles and docs/KYC.md,
# "Funder profiles"). It uses only that funder's rules:
#
# - report_fields: the only demographic fields in the report. Counts only,
#   never a member's answers.
# - small_count_threshold: the funder's own threshold, never lower than the
#   global one.
# - amount_reporting: "bands" (counts of members per amount band) or
#   "totals" (sums per program and year, never a per-person amount).
# - requires_member_consent: a member counts only with a live FunderConsent.
#   Departed members and the delete-time aggregates can't show consent, so
#   they are left out of such a report.
#
# The members of a funder's report are the members with a participation that
# names this funder, or that names no funder in a program whose only funder
# is this one.
#
# The demographic counts come from the reporting run (DemographicsReport),
# because only that run can open the vault. The delete-time aggregates and
# the amounts come from the database. The admin page previews the report: no
# export and no send yet.
module FunderReport
  Report = Data.define(:profile, :generated_at, :demographics, :departed, :delete_time, :amounts, :notes)

  class << self
    def build(profile)
      profile = FunderProfiles.find!(profile) unless profile.is_a?(FunderProfiles::Profile)
      run = DemographicReport.latest
      from_run = run&.results&.dig("funders", profile.key)
      notes = []
      notes << "No reporting run has counted this funder yet. Run bin/rails demographics:report." if from_run.nil?
      if profile.consent_required?
        notes << "Only members who gave consent count. Departed members and the delete-time aggregates are left out, " \
                 "because their consent can't be shown."
      end

      Report.new(profile:, generated_at: run&.generated_at, demographics: from_run&.dig("active"),
                 departed: from_run&.dig("departed"), delete_time: delete_time(profile), amounts: amounts(profile), notes:)
    end

    # The live members who count for this funder.
    def member_ids(profile)
      scope = ProgramParticipation.live.merge(funded(ProgramParticipation, profile))
      scope = scope.where(user_id: FunderConsent.user_ids_for(profile.key)) if profile.consent_required?
      scope.distinct.pluck(:user_id)
    end

    # Keeps only the funder's report fields of a tally ({ "respondents",
    # "fields" }).
    def restrict(tally, profile)
      { "respondents" => tally.fetch("respondents", 0), "fields" => tally.fetch("fields", {}).slice(*profile.report_fields) }
    end

    # The demographic results of the reporting run for this funder, from the
    # raw tallies of that run. DemographicsReport calls it.
    def run_results(profile, active_tally, departed)
      {
        "threshold"        => profile.threshold,
        "consent_required" => profile.consent_required?,
        "active"           => DemographicsReport.suppress(restrict(active_tally, profile), profile.threshold),
        "departed"         => departed_results(profile, departed)
      }
    end

    private

    # Records that name this funder, and records with no funder in a program
    # whose only funder is this one. A record with no funder in a program
    # with more than one funder counts for none of them.
    def funded(model, profile)
      sole = profile.programs.select { |program| DataRetention.funders_for_program(program) == [profile.key] }
      model.where(program: profile.programs, funder: profile.key).or(model.where(program: sole, funder: [nil, ""]))
    end

    def departed_results(profile, departed)
      return nil if profile.consent_required?

      cohorts = departed.select { |cohort, _| profile.programs.any? { |program| cohort.start_with?("#{program}-") } }
      cohorts.sort.to_h.transform_values { |totals| DemographicsReport.suppress(restrict(totals, profile), profile.threshold) }
    end

    # The delete-time aggregates of the funder's programs, per cohort.
    def delete_time(profile)
      return nil if profile.consent_required?

      fields = ["outcome"]
      fields << "age_band" if profile.report_fields.include?("age_band")
      fields << "amount_band" unless profile.totals?
      cells = DeleteTimeAggregate.where(program: profile.programs).to_a
      cells.group_by { |cell| "#{cell.program}-#{cell.year}" }.sort.to_h.transform_values do |group|
        tally = { "respondents" => group.sum(&:count), "fields" => fields.index_with { |field| count_by(group, field) } }
        DemographicsReport.suppress(tally, profile.threshold)
      end
    end

    def count_by(cells, field)
      cells.each_with_object(Hash.new(0)) { |cell, counts| counts[cell.public_send(field)] += cell.count }
    end

    # Bands: members per amount band, per program and year. Totals: the sum
    # per program and year, shown only when at least threshold members got
    # money, so a total can't be one person's amount.
    def amounts(profile)
      rows = funded_disbursements(profile).group_by { |row| "#{row.program}-#{row.disbursed_on.year}" }
      rows.sort.to_h.transform_values do |group|
        per_person = group.group_by { |row| row.user_id || "detached-#{row.id}" }.transform_values { |items| items.sum(&:amount_cents) }
        if profile.totals?
          recipients = per_person.size
          { "recipients" => recipients >= profile.threshold ? recipients : nil,
            "total_cents" => recipients >= profile.threshold ? per_person.values.sum : nil,
            "currency" => group.map(&:currency).uniq.join(", ") }
        else
          bands = per_person.values.each_with_object(Hash.new(0)) { |cents, counts| counts[DataRetention.amount_band(cents)] += 1 }
          DemographicsReport.suppress({ "respondents" => per_person.size, "fields" => { "amount_band" => bands } }, profile.threshold)
        end
      end
    end

    def funded_disbursements(profile)
      scope = funded(GrantDisbursement, profile)
      scope = scope.where(user_id: FunderConsent.user_ids_for(profile.key)) if profile.consent_required?
      scope.to_a
    end

  end
end
