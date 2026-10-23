# frozen_string_literal: true

# The demographics vault: self-reported answers that funders count (age band,
# gender identity, and the fields in config/demographics.yml).
#
# The vault is write-only for the app. It seals each member's answers with a
# public key (see DemographicsVault::Envelope) and keeps no way to open them.
# Only DemographicsReport, run with the private key (DemographicsVault::Reader)
# outside the web app, opens the envelopes, and it writes only aggregates
# with small-count suppression. No admin page, serializer, export or console
# helper shows a member's answers. See docs/KYC.md for the threat model.
#
#   member answers -> record (sealed) -> reporting run -> aggregates only
#   member leaves  -> fold! (envelope parked without a link to the person)
#                  -> next reporting run counts it into the departed totals
module DemographicsVault
  PREFER_NOT_TO_SAY = "prefer_not_to_say"
  SELF_DESCRIBE = "self_describe"
  NOT_ANSWERED = "not_answered"
  UNKNOWN_AGE = "unknown"
  SELF_DESCRIPTION_MAX = 100
  COHORT_MAX = 50

  # The app has no public key, so it can't seal answers.
  class NotConfigured < StandardError; end

  Result = Data.define(:errors) do
    def success? = errors.empty?
  end

  # What fold! did: folded is false when the member had no answers.
  Fold = Data.define(:folded)

  class << self
    # Set in specs. In other environments the key comes from credentials or
    # config/demographics.yml.
    attr_writer :public_key

    def config = @config ||= Rails.application.config_for(:demographics)

    def reset!
      @config = nil
      @public_key = nil
    end

    def fields = config.fetch(:fields).map { |field| field.to_h.symbolize_keys }

    def small_count_threshold = Integer(config.fetch(:small_count_threshold))

    def available? = public_key.present?

    def public_key
      return @public_key if defined?(@public_key) && @public_key

      pem = Rails.application.credentials.dig(:demographics, :public_key).presence || config[:public_key].presence
      pem ||= DevelopmentKeys.public_pem if Rails.env.development?
      @public_key = pem && OpenSSL::PKey.read(pem)
    end

    # The options a member can pick for a field, in form order.
    def options_for(field)
      options = Array(field[:options]).map(&:to_s)
      options << SELF_DESCRIBE if field[:self_describe]
      options << PREFER_NOT_TO_SAY
    end

    # Strong-parameter keys for the member form.
    def permitted_params
      fields.flat_map do |field|
        keys = [field[:type] == "multi" ? { field[:key] => [] } : field[:key]]
        keys << "#{field[:key]}_self_description" if field[:self_describe]
        keys
      end
    end

    # The member's age band now, from their birthday. The vault stores only
    # the band.
    def age_band(birthday, on: Date.current)
      return UNKNOWN_AGE if birthday.nil?

      age = on.year - birthday.year - (on.strftime("%m%d") < birthday.strftime("%m%d") ? 1 : 0)
      starts = config.fetch(:age_band_starts).map { |start| Integer(start) }.sort
      index = starts.rindex { |start| age >= start }
      return UNKNOWN_AGE if index.nil?

      upper = starts[index + 1]
      upper ? "#{starts[index]}-#{upper - 1}" : "#{starts[index]}+"
    end

    # Seals and stores the member's answers, replacing the ones before. The
    # member must agree each time. Returns a Result whose errors are keyed by
    # field.
    def record(user, answers, consent:)
      raise NotConfigured, "No demographics public key is set" unless available?
      return Result.new(errors: { consent: I18n.t("demographics.form.consent_error") }) unless consent

      normalized, errors = normalize(answers.to_h.stringify_keys)
      return Result.new(errors:) if errors.any?

      payload = { "v" => 1, "age_band" => age_band(user.birthday), "recorded_year" => Date.current.year, "answers" => normalized }
      envelope = Envelope.seal(payload, public_key)
      record = DemographicRecord.find_or_initialize_by(user:)
      record.update!(envelope:, key_id: Envelope.key_id(public_key))
      Result.new(errors: {})
    end

    # The member takes their answers back. They are not counted anywhere.
    def withdraw!(user) = DemographicRecord.where(user:).delete_all.positive?

    # When the member last saved answers, or nil. This says nothing about the
    # answers.
    def answered_at(user) = DemographicRecord.where(user:).pick(:updated_at)

    # The delete-time step (see the deletion pipeline in docs/KYC.md). Moves
    # the member's sealed envelope to the fold queue, with no link to the
    # member, then destroys their record. The next reporting run opens the
    # envelope and adds its bands to the departed totals for each cohort (for
    # example "2026" or "ganymede-2026"). Call it before the identity is
    # severed. Safe to call twice.
    #
    # The app can't open the envelope, so this returns no bands: see
    # docs/KYC.md for why.
    def fold!(user, cohorts: [Date.current.year.to_s])
      cohorts = Array(cohorts).map { |cohort| cohort.to_s.strip.first(COHORT_MAX) }.compact_blank.uniq
      DemographicRecord.transaction do
        record = DemographicRecord.lock.find_by(user_id: user.id)
        return Fold.new(folded: false) if record.nil?

        DemographicFold.create!(envelope: record.envelope, key_id: record.key_id, cohorts:)
        record.destroy!
      end
      Fold.new(folded: true)
    end

    private

    def normalize(answers)
      errors = {}
      normalized = fields.to_h do |field|
        key = field[:key]
        value = field[:type] == "multi" ? normalize_multi(field, answers[key], errors) : normalize_choice(field, answers[key], errors)
        [key, value]
      end
      fields.select { |field| field[:self_describe] }.each do |field|
        text = answers["#{field[:key]}_self_description"].to_s.strip.first(SELF_DESCRIPTION_MAX).presence
        selected = Array(normalized[field[:key]]).include?(SELF_DESCRIBE)
        normalized["#{field[:key]}_self_description"] = (text if selected)
      end
      [normalized, errors]
    end

    def normalize_choice(field, value, errors)
      value = value.to_s.strip.presence
      return nil if value.nil?
      return value if options_for(field).include?(value)

      errors[field[:key].to_sym] = I18n.t("demographics.form.invalid")
      nil
    end

    def normalize_multi(field, values, errors)
      values = Array(values).map { |value| value.to_s.strip }.compact_blank.uniq
      return nil if values.empty?

      unless (values - options_for(field)).empty?
        errors[field[:key].to_sym] = I18n.t("demographics.form.invalid")
        return nil
      end
      values.include?(PREFER_NOT_TO_SAY) ? [PREFER_NOT_TO_SAY] : values
    end

  end
end
