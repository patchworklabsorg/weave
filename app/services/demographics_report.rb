# frozen_string_literal: true

# The reporting run for the demographics vault (see DemographicsVault). It is
# the only code that opens envelopes, and it writes only aggregates:
#
#   1. Open the sealed departed totals (DemographicDepartedTotal).
#   2. Count the parked envelopes of deleted members (DemographicFold) into
#      those totals for their cohorts, delete them, and seal the totals again.
#   3. Count the live envelopes of current members.
#   4. Apply small-count suppression and save a DemographicReport.
#
# Run it with `bin/rails demographics:report` in a process that has the
# private key. The web app never has the key, so it can't run this.
module DemographicsReport
  # Envelopes of departed totals use their own associated data, so a
  # member's envelope can't be put in their place.
  DEPARTED_AAD = "weave-demographics-departed-v1"
  # The sealed totals grow with the cohorts. They are padded to a multiple of
  # this size, so the size says little about the counts.
  DEPARTED_BLOCK = 4096
  # pg_advisory_xact_lock key: one reporting run at a time.
  LOCK_KEY = 110_110

  # The sealed departed totals can't be opened with the key of this run. The
  # run stops, so it never replaces the totals with empty ones.
  class DepartedTotalsUnreadable < StandardError; end

  class << self
    # reader is a DemographicsVault::Reader. Returns the saved report.
    def generate!(reader:, run_by: nil, threshold: DemographicsVault.small_count_threshold)
      DemographicReport.transaction do
        DemographicReport.connection.execute("SELECT pg_advisory_xact_lock(#{LOCK_KEY})")

        totals_row = DemographicDepartedTotal.order(:id).first_or_initialize
        departed = totals_row.new_record? ? {} : open_departed(reader, totals_row)
        unreadable, folds_counted = count_folds!(reader, departed)
        save_departed!(reader, totals_row, departed) if folds_counted.positive?

        active = Tally.new
        DemographicRecord.find_each do |record|
          payload = open_envelope(reader, record.envelope)
          payload ? active.add(payload) : unreadable += 1
        end

        DemographicReport.create!(
          generated_at: Time.current, threshold:, run_by:, unreadable_count: unreadable, folds_counted:,
          results: { "active" => suppress(active.to_h, threshold), "departed" => departed_results(departed, threshold) }
        )
      end
    end

    # Hides every count from 1 to threshold - 1. When a field has exactly one
    # hidden count, the next smallest count is hidden too, so the hidden one
    # can't be worked out from the total. When there are fewer respondents
    # than the threshold, everything is hidden. A hidden count is nil.
    def suppress(tally, threshold)
      respondents = tally.fetch("respondents", 0)
      fields = tally.fetch("fields", {})
      if respondents < threshold
        return { "respondents" => nil, "fields" => fields.transform_values { |counts| counts.transform_values { nil } } }
      end

      { "respondents" => respondents, "fields" => fields.transform_values { |counts| suppress_cells(counts, threshold) } }
    end

    private

    def open_envelope(reader, envelope)
      reader.open(envelope)
    rescue DemographicsVault::Envelope::Unreadable
      nil
    end

    def open_departed(reader, row)
      reader.open(row.envelope, aad: DEPARTED_AAD)
    rescue DemographicsVault::Envelope::Unreadable
      raise DepartedTotalsUnreadable, "The departed totals (key #{row.key_id}) can't be opened with key #{reader.key_id}"
    end

    def save_departed!(reader, row, departed)
      size = ((departed.to_json.bytesize / DEPARTED_BLOCK) + 1) * DEPARTED_BLOCK
      row.update!(envelope: reader.seal(departed, size:, aad: DEPARTED_AAD), key_id: reader.key_id)
    end

    def suppress_cells(counts, threshold)
      hidden = counts.select { |_, count| count.positive? && count < threshold }.keys
      if hidden.one?
        next_smallest = counts.reject { |value, count| hidden.include?(value) || count.zero? }.min_by { |_, count| count }
        hidden << next_smallest.first if next_smallest
      end
      counts.to_h { |value, count| [value, hidden.include?(value) ? nil : count] }
    end

    # Adds each parked envelope to the departed totals (in memory) and
    # deletes it. An envelope this key can't open stays for a later run.
    # Returns [unreadable, counted].
    def count_folds!(reader, departed)
      unreadable = 0
      counted = 0
      DemographicFold.find_each do |fold|
        payload = open_envelope(reader, fold.envelope)
        next unreadable += 1 if payload.nil?
        # Count it only if this run deleted it, so a member is never counted
        # twice.
        next unless DemographicFold.where(id: fold.id).delete_all == 1

        add_departed(departed, fold.cohorts, payload)
        counted += 1
      end
      [unreadable, counted]
    end

    def add_departed(departed, cohorts, payload)
      tally = Tally.new.add(payload).to_h
      Array(cohorts).each do |cohort|
        totals = departed[cohort] ||= { "respondents" => 0, "fields" => {} }
        totals["respondents"] += tally["respondents"]
        tally["fields"].each do |field, counts|
          cells = totals["fields"][field] ||= {}
          counts.each { |value, count| cells[value] = cells.fetch(value, 0) + count }
        end
      end
    end

    def departed_results(departed, threshold)
      departed.sort.to_h.transform_values { |totals| suppress(totals, threshold) }
    end

  end

  # Counts payloads in memory. It keeps only counts, so nothing that is
  # tied to one envelope outlives #add.
  class Tally
    def initialize
      @respondents = 0
      @fields = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    end

    def add(payload)
      @respondents += 1
      @fields["age_band"][payload["age_band"].presence || DemographicsVault::UNKNOWN_AGE] += 1
      answers = payload.fetch("answers", {})
      DemographicsVault.fields.each do |field|
        values = Array(answers[field[:key]]).presence || [DemographicsVault::NOT_ANSWERED]
        values.each { |value| @fields[field[:key]][value] += 1 }
      end
      self
    end

    def to_h = { "respondents" => @respondents, "fields" => @fields.transform_values(&:to_h) }

  end
end
