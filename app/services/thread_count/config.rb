# frozen_string_literal: true

# The Thread Count weights and thresholds from config/thread_count.yml. All
# values there are placeholders until the open question on weights is
# decided.
module ThreadCount
  class Config
    # Raised for a kind or level that the file does not list.
    class UnknownWeight < StandardError; end

    class << self
      def current
        @current ||= new(Rails.application.config_for(:thread_count))
      end

      # For specs: use other values for the duration of the block.
      def with(overrides)
        previous = @current
        @current = new(current.to_h.deep_merge(overrides.deep_symbolize_keys))
        yield
      ensure
        @current = previous
      end

    end

    def initialize(values)
      @values = values.to_h.deep_symbolize_keys
    end

    def to_h = @values

    def member_vouch_threshold = @values.fetch(:member_vouch_threshold).to_f

    def senior_staff_roles = Array(@values[:senior_staff_roles]).map(&:to_s)

    def project_event_services = Array(@values[:project_event_services]).map(&:to_s)

    # Levels a kind takes, or [] for a kind without levels.
    def levels(kind)
      case kind.to_s
      when "staff_vouch" then %w[senior_staff staff]
      when "moderation_case" then table(:moderation_case_weights).keys.map(&:to_s)
      when "external_signal" then table(:external_signal_weights).keys.map(&:to_s)
      else []
      end
    end

    def weight(kind, level = nil)
      value = case kind.to_s
              when "board_vouch" then table(:vouch_weights)[:board]
              when "staff_vouch" then table(:vouch_weights)[level.to_s.to_sym] if levels(kind).include?(level.to_s)
              when "member_vouch" then table(:vouch_weights)[:member]
              when "moderation_case" then table(:moderation_case_weights)[level.to_s.to_sym]
              when "external_signal" then table(:external_signal_weights)[level.to_s.to_sym]
              when "reversal" then 0
              else table(:project_weights)[kind.to_s.to_sym]
              end
      raise UnknownWeight, "No Thread Count weight for #{kind}/#{level}" if value.nil?

      value.to_f
    end

    def weight?(kind, level = nil)
      weight(kind, level)
      true
    rescue UnknownWeight
      false
    end

    # Kinds whose entries never fade (no_decay_kinds).
    def no_decay_kinds = Array(@values[:no_decay_kinds]).map(&:to_s)

    # Days for an entry of this kind to fade by half, or nil when it never
    # fades: a kind in no_decay_kinds, or a null in half_life_days_by_kind.
    def half_life_days(kind)
      return nil if no_decay_kinds.include?(kind.to_s)

      overrides = table(:half_life_days_by_kind)
      value = overrides.key?(kind.to_s.to_sym) ? overrides[kind.to_s.to_sym] : @values[:half_life_days]
      value&.to_f
    end

    private

    def table(name) = @values[name] || {}

  end
end
